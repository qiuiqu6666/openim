package interaction

import (
	"context"
	"errors"
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"sort"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
)

// Only explicit authenticated directional boundaries can shrink a range. Batch
// the same protocol across chats; a missing packet is an error for that chat.
func (m *MsgSyncer) visibleMessageRanges(ctx context.Context, ranges map[string][2]int64) (map[string][2]int64, map[string]error, []string) {
	visible, conflicts := make(map[string][2]int64), make(map[string][2]int64)
	failed := make(map[string]error)
	ids := make([]string, 0, len(ranges))
	for id := range ranges {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	var cached map[string]*model_struct.LocalConversation
	if reader, ok := m.db.(db_interface.MessageRecoveryBoundsReader); ok {
		rows, err := reader.GetMessageRecoveryBounds(ctx)
		if err != nil {
			for _, id := range ids {
				failed[id] = err
			}
			return visible, failed, ids
		}
		cached = make(map[string]*model_struct.LocalConversation, len(rows))
		for _, row := range rows {
			if row != nil {
				cached[row.ConversationID] = row
			}
		}
		// Recent/pinned chats reach the first batch before dormant history.
		sort.SliceStable(ids, func(i, j int) bool {
			a, b := cached[ids[i]], cached[ids[j]]
			if a == nil {
				return false
			}
			if b == nil {
				return true
			}
			if a.IsPinned != b.IsPinned {
				return a.IsPinned
			}
			return a.LatestMsgSendTime > b.LatestMsgSendTime
		})
	}
	for _, id := range ids {
		if err := yieldMessageSyncPage(ctx); err != nil {
			failed[id] = err
			continue
		}
		r := ranges[id]
		r[0] = max(1, r[0])
		if m.db != nil && !IsNotification(id) {
			var row *model_struct.LocalConversation
			var err error
			if cached != nil {
				row = cached[id]
			} else {
				row, err = m.db.GetConversation(ctx, id)
			}
			if err != nil && !errors.Is(err, errs.ErrRecordNotFound) {
				failed[id] = err
				continue
			}
			if row != nil {
				r[0] = max(r[0], row.MinSeq)
				if row.MaxSeq > 0 && r[1] > row.MaxSeq {
					conflicts[id] = r
				}
			}
		}
		visible[id] = r
	}
	m.prioritizeConversations(ids, nil)
	if len(conflicts) == 0 {
		return visible, failed, ids
	}
	var conflictingIDs []string
	for _, id := range ids {
		if _, ok := conflicts[id]; ok {
			conflictingIDs = append(conflictingIDs, id)
		}
	}
	for begin := 0; begin < len(conflictingIDs); begin += latestMessageBatchSize {
		batch := make(map[string][2]int64)
		for _, id := range conflictingIDs[begin:min(begin+latestMessageBatchSize, len(conflictingIDs))] {
			batch[id] = conflicts[id]
		}
		m.resolveVisibilityBatch(ctx, batch, failed)
		for id, r := range batch {
			if failed[id] == nil {
				visible[id] = r
			}
		}
	}
	return visible, failed, ids
}

func (m *MsgSyncer) resolveVisibilityBatch(ctx context.Context, ranges map[string][2]int64, failed map[string]error) {
	for _, ascending := range []bool{false, true} {
		if err := yieldMessageSyncPage(ctx); err != nil {
			for id := range ranges {
				failed[id] = err
			}
			return
		}
		order := sdkws.PullOrder_PullOrderDesc
		if ascending {
			order = sdkws.PullOrder_PullOrderAsc
		}
		req := &msg.GetSeqMessageReq{UserID: m.loginUserID, Order: order}
		for id, r := range ranges {
			if failed[id] != nil || r[0] > r[1] {
				continue
			}
			seq := r[0]
			if ascending {
				seq = r[1]
			}
			req.Conversations = append(req.Conversations, &msg.ConversationSeqs{ConversationID: id, Seqs: []int64{seq}})
		}
		if len(req.Conversations) == 0 {
			return
		}
		var resp msg.GetSeqMessageResp
		if err := m.longConnMgr.SendReqWaitResp(ctx, req, constant.PullMsgBySeqList, &resp); err != nil {
			for _, row := range req.Conversations {
				failed[row.ConversationID] = err
			}
			return
		}
		for _, row := range req.Conversations {
			id := row.ConversationID
			packet := resp.Msgs[id]
			if packet == nil || packet.EndSeq < 0 {
				failed[id] = fmt.Errorf("invalid visibility response for %q", id)
				continue
			}
			if !packet.IsEnd {
				continue
			}
			r := ranges[id]
			if ascending {
				r[1] = min(r[1], packet.EndSeq)
			} else {
				r[0] = max(r[0], packet.EndSeq)
			}
			ranges[id] = r
		}
	}
}
