package conversation_msg

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"sort"
)

type messageWindowReader interface {
	ReadMessageWindow(context.Context, string, int, int64) (*model_struct.MessageWindowRead, error)
}

func (c *Conversation) messageWindow(ctx context.Context, req sdk.GetAdvancedHistoryMessageListParams) (*sdk.GetAdvancedHistoryMessageListCallback, error) {
	reader, ok := c.db.(messageWindowReader)
	if !ok {
		return nil, fmt.Errorf("atomic message windows unavailable")
	}
	if req.ConversationID == "" || req.StartClientMsgID != "" || req.ScanCursor != nil {
		return nil, fmt.Errorf("window requires an unanchored conversation")
	}
	target := req.TargetWatermark
	latestServerSeq := int64(0)
	var visible [2]int64
	source := "local"
	remoteEmpty := false
	if !req.LocalSnapshot && c.LongConnMgr != nil && c.LongConnMgr.IsConnected() {
		if target <= 0 {
			var newest sdkws.GetMaxSeqResp
			if err := c.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{UserID: c.loginUserID}, constant.GetNewestSeq, &newest); err != nil {
				return nil, err
			}
			var exists bool
			target, exists = newest.MaxSeqs[req.ConversationID]
			if !exists {
				// Omission from a global summary is not an empty-conversation
				// receipt. Require the existing directional permission boundary.
				bounds, err := c.ResolveVisibleMessageRange(ctx, c.loginUserID, req.ConversationID, [2]int64{1, 1})
				if err != nil {
					return nil, err
				}
				if bounds[0] <= bounds[1] {
					return nil, fmt.Errorf("conversation watermark absent without empty-range evidence")
				}
			}
		}
		remoteEmpty = target == 0
		latestServerSeq = target
		if target > 0 {
			var err error
			visible, err = c.prepareMessageWindow(ctx, req.ConversationID, req.Count, target)
			if err != nil {
				return nil, err
			}
			target = max(0, visible[1])
			remoteEmpty = visible[0] > visible[1]
			if !remoteEmpty {
				req.Count = int(visible[1] - visible[0] + 1)
			}
		}
		source = "remote"
	}
	read, err := reader.ReadMessageWindow(ctx, req.ConversationID, req.Count, target)
	if err != nil {
		return nil, err
	}
	if read.Conversation.IsPrivateChat {
		req.Window = false
		return c.getAdvancedHistoryMessageList(ctx, req, false)
	}
	if remoteEmpty {
		read.Rows = nil
		read.Conversation.MinSeq = max(read.Conversation.MinSeq, target+1)
	}
	result := buildMessageWindow(req, read, target, source, remoteEmpty)
	target = result.Window.TargetWatermark
	// A tail made only of tombstones/control messages is not an empty chat.
	// Search at most two more bounded pages under the original fixed watermark.
	step := req.Count
	for attempt := 1; attempt < 3 && result.Window.Publishable && len(result.MessageList) == 0 && !result.IsEnd; attempt++ {
		if source == "remote" {
			if _, err := c.prepareMessageWindow(ctx, req.ConversationID, step, result.Window.LowerBound-1); err != nil {
				return nil, err
			}
		}
		req.Count += step
		read, err = reader.ReadMessageWindow(ctx, req.ConversationID, req.Count, target)
		if err != nil {
			return nil, err
		}
		result = buildMessageWindow(req, read, target, source, remoteEmpty)
	}
	if result.Window.Publishable && len(result.MessageList) == 0 && !result.IsEnd {
		if err := setInvisibleWindowCursor(result, read); err != nil {
			return nil, err
		}
	}
	result.Window.LatestServerSeq = latestServerSeq
	return result, nil
}

func setInvisibleWindowCursor(result *sdk.GetAdvancedHistoryMessageListCallback, read *model_struct.MessageWindowRead) error {
	for _, row := range read.Rows {
		if row.Seq == result.Window.LowerBound && row.SendTime > 0 && row.ClientMsgID != "" {
			result.ScanLimited = true
			result.ScanCursor = &sdk.HistoryScanCursor{ConversationID: result.Window.ConversationID, ClientMsgID: row.ClientMsgID, Seq: row.Seq, SendTime: row.SendTime}
			return nil
		}
	}
	return fmt.Errorf("invisible window has no resumable history boundary")
}

// Re-read the bounded remote window even when all bodies exist locally: seq
// orders messages, but cannot detect an offline recall of an earlier message.
// Existing durable recall/read overlays win over an older in-flight response.
func (c *Conversation) prepareMessageWindow(ctx context.Context, id string, count int, target int64) ([2]int64, error) {
	r := [2]int64{max(1, target-int64(min(max(count, 1), 100))+1), target}
	release, err := c.LockMessageHistory(ctx, id, true)
	if err != nil {
		return r, err
	}
	defer release()
	r, err = c.ResolveVisibleMessageRange(ctx, c.loginUserID, id, r)
	if err != nil || r[0] > r[1] {
		return r, err
	}
	seqs := getLostSeqListWithLimitLength(r[0], r[1], nil, false)
	var rows []*model_struct.LocalChatLog
	result := &sdk.GetAdvancedHistoryMessageListCallback{}
	c.fetchAndMergeMissingMessages(ctx, id, seqs, false, count, 0, &rows, result)
	if result.ErrCode != 0 {
		return r, historyFetchError(result.ErrMsg)
	}
	return r, nil
}

func buildMessageWindow(req sdk.GetAdvancedHistoryMessageListParams, read *model_struct.MessageWindowRead, target int64, source string, remoteEmpty bool) *sdk.GetAdvancedHistoryMessageListCallback {
	conversation := read.Conversation
	result := &sdk.GetAdvancedHistoryMessageListCallback{LocalSnapshot: req.LocalSnapshot, MessageList: []*sdk_struct.MsgStruct{}}
	w := &sdk.MessageWindow{Version: 1, ConversationID: req.ConversationID, Source: source, Covered: [][2]int64{}, Missing: [][2]int64{}}
	result.Window = w
	if target <= 0 && !remoteEmpty {
		target = conversation.MaxSeq
		var latest sdk_struct.MsgStruct
		if json.Unmarshal([]byte(conversation.LatestMsg), &latest) == nil {
			target = max(target, latest.Seq)
		}
		for _, row := range read.Rows {
			target = max(target, row.Seq)
		}
	}
	w.TargetWatermark = target
	w.LowerBound = max(1, conversation.MinSeq, target-int64(req.Count)+1)
	w.VisibilityKey = fmt.Sprintf("%d:%d:%t", conversation.MinSeq, conversation.MaxSeq, conversation.IsPrivateChat)
	stored := map[int64]*model_struct.LocalChatLog{}
	for _, row := range read.Rows {
		if row.Seq >= w.LowerBound && row.Seq <= target {
			stored[row.Seq] = row
		}
	}
	appendRange := func(ranges *[][2]int64, seq int64) {
		if len(*ranges) > 0 && (*ranges)[len(*ranges)-1][1]+1 == seq {
			(*ranges)[len(*ranges)-1][1] = seq
		} else {
			*ranges = append(*ranges, [2]int64{seq, seq})
		}
	}
	for seq := w.LowerBound; seq <= target; seq++ {
		row, exists := stored[seq]
		if !exists {
			appendRange(&w.Missing, seq)
			continue
		}
		appendRange(&w.Covered, seq)
		if row.Status >= constant.MsgStatusHasDeleted || row.ContentType == constant.Typing {
			continue
		}
		message := LocalChatLogToMsgStruct(row)
		if message.AttachedInfoElem.IsPrivateChat {
			continue
		}
		result.MessageList = append(result.MessageList, message)
	}
	sort.SliceStable(result.MessageList, func(i, j int) bool { return result.MessageList[i].Seq < result.MessageList[j].Seq })
	appendLocalWindowMessages(result, read, remoteEmpty)
	w.Publishable = !conversation.IsPrivateChat && len(w.Missing) == 0 && (target > 0 || remoteEmpty)
	w.Readiness = "preparing"
	if w.Publishable {
		w.Readiness = "ready"
	}
	w.CoverageStatus = "partial"
	if len(w.Missing) == 0 && (target > 0 || remoteEmpty) {
		w.CoverageStatus = "covered"
	}
	result.SnapshotReady = w.Publishable
	result.IsEnd = w.Publishable && (remoteEmpty || w.LowerBound <= max(1, conversation.MinSeq))
	w.EmptyConfirmed = result.IsEnd && len(result.MessageList) == 0
	// Identity, not a sortable server mutation cursor. SDK window generations
	// fence response ordering; durable notification cursors protect mutations.
	payload, _ := json.Marshal(struct {
		Window *sdk.MessageWindow
		Rows   []*sdk_struct.MsgStruct
	}{w, result.MessageList})
	digest := sha256.Sum256(payload)
	w.SnapshotRevision = hex.EncodeToString(digest[:])
	return result
}
