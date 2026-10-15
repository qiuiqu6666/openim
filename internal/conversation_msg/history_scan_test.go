package conversation_msg

import (
	"context"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/cache"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

type scanHistoryDB struct {
	*recoveryDB
	starts  []int64
	visible map[int64]bool
}

func (d *scanHistoryDB) GetMessageList(_ context.Context, _ string, count int, _ int64, startSeq int64, _ string, reverse bool) ([]*model_struct.LocalChatLog, error) {
	d.starts = append(d.starts, startSeq)
	var rows []*model_struct.LocalChatLog
	step := int64(-1)
	if reverse {
		step = 1
	}
	for seq := startSeq + step; seq >= 1 && seq <= 40 && len(rows) < count; seq += step {
		status := constant.MsgStatusHasDeleted
		if d.visible[seq] {
			status = constant.MsgStatusSendSuccess
		}
		rows = append(rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprintf("row-%d", seq), Seq: seq, SendTime: seq,
			Status: int32(status), ContentType: constant.Text, Content: `{"content":"visible"}`})
	}
	return rows, nil
}

func (d *scanHistoryDB) MaintainMessageCache(context.Context, string, []string) error { return nil }

func TestHistoryScanYieldsAndResumesThroughDeletedRanges(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		for _, withVisible := range []bool{false, true} {
			t.Run(fmt.Sprintf("reverse=%v/visible=%v", reverse, withVisible), func(t *testing.T) {
				c, base, _, cmd := recoveryConversation(t)
				d := &scanHistoryDB{recoveryDB: base, visible: map[int64]bool{}}
				firstSeq, startSeq := int64(40), int64(41)
				if reverse {
					firstSeq, startSeq = 1, 0
				}
				if withVisible {
					d.visible[firstSeq] = true
				}
				c.db = d
				c.maxSeqRecorder.Set("chat", 40)
				c.messagePullForwardEndSeqMap = cache.NewConversationSeqContextCache()
				c.messagePullReverseEndSeqMap = cache.NewConversationSeqContextCache()
				c.messagePullForwardEndSeqMap.Store("chat", 0, startSeq)
				c.messagePullReverseEndSeqMap.Store("chat", 0, startSeq)
				result := &sdk.GetAdvancedHistoryMessageListCallback{}
				rows, err := c.fetchMessagesWithGapCheck(cmd.Ctx, "chat", 4, startSeq, startSeq, "initial", reverse, 0, result)
				if err != nil || !result.ScanLimited || result.IsEnd || result.ScanCursor == nil {
					t.Fatalf("scan budget became error/end: rows=%v result=%+v err=%v", rows, result, err)
				}
				wantVisible := 0
				if withVisible {
					wantVisible = 1
				}
				if len(rows) != wantVisible || len(d.starts) != MaxRecursionDepth+1 {
					t.Fatalf("lost visible rows or exceeded read budget: rows=%d reads=%d", len(rows), len(d.starts))
				}
				previous := result.ScanCursor.Seq
				// Resume by explicit scan position, even if the deleted anchor was cleaned
				// from the local table. No GetMessage lookup is available on this fake.
				for attempt := 0; attempt < 10; attempt++ {
					resumed, err := c.getAdvancedHistoryMessageList(cmd.Ctx, sdk.GetAdvancedHistoryMessageListParams{
						ConversationID: "chat", Count: 4, ScanCursor: result.ScanCursor,
					}, reverse)
					if err != nil {
						t.Fatal(err)
					}
					if len(resumed.MessageList) != 0 {
						t.Fatal("deleted scan rows entered the visible page")
					}
					if resumed.IsEnd {
						if resumed.ScanLimited || resumed.ScanCursor != nil {
							t.Fatal("completed page retains a continuation")
						}
						return
					}
					if !resumed.ScanLimited || resumed.ScanCursor == nil {
						t.Fatal("lost continuation")
					}
					next := resumed.ScanCursor.Seq
					if (!reverse && next >= previous) || (reverse && next <= previous) {
						t.Fatal("scan did not advance")
					}
					previous, result = next, resumed
				}
				t.Fatal("scan never reached the real end")
			})
		}
	}
}

func TestHistoryScanRejectsCrossConversationAndDirection(t *testing.T) {
	c := &Conversation{}
	for _, cursor := range []*sdk.HistoryScanCursor{
		{ConversationID: "other", ClientMsgID: "row", Seq: 10, SendTime: 10},
		{ConversationID: "chat", Reverse: true, ClientMsgID: "row", Seq: 10, SendTime: 10},
		{ConversationID: "chat", ClientMsgID: "row", Seq: 0, SendTime: 10},
	} {
		_, err := c.getAdvancedHistoryMessageList(context.Background(), sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 4, ScanCursor: cursor}, false)
		if err == nil {
			t.Fatal("accepted an invalid continuation")
		}
	}
}
