package interaction

import (
	"context"
	"fmt"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/log"
)

// An empty preview alone is not coverage. Revalidate its full pending window
// through the authenticated directional history API. This preserves cleared or
// membership-restricted history without waiving genuine holes or transport errors.
func (m *MsgSyncer) resolveEmptySyncPreviews(ctx context.Context, batch, visible map[string][2]int64, resp *sdkws.PullMessageBySeqsResp) error {
	if resp == nil {
		return nil
	}
	pending := make(map[string][2]int64)
	for id := range batch {
		if packet := resp.Msgs[id]; packet != nil && len(packet.Msgs) == 0 {
			pending[id] = visible[id]
		}
	}
	if len(pending) == 0 {
		return nil
	}
	closed := 0
	for _, ascending := range []bool{false, true} {
		req := &msg.GetSeqMessageReq{UserID: m.loginUserID, Order: sdkws.PullOrder_PullOrderDesc}
		if ascending {
			req.Order = sdkws.PullOrder_PullOrderAsc
		}
		for id, r := range pending {
			if r[0] > r[1] {
				continue
			}
			seq := r[0]
			if ascending {
				seq = r[1]
			}
			req.Conversations = append(req.Conversations, &msg.ConversationSeqs{ConversationID: id, Seqs: []int64{seq}})
		}
		if len(req.Conversations) == 0 {
			break
		}
		var boundary msg.GetSeqMessageResp
		if err := m.longConnMgr.SendReqWaitResp(ctx, req, constant.PullMsgBySeqList, &boundary); err != nil {
			return err
		}
		for _, conv := range req.Conversations {
			packet := boundary.Msgs[conv.ConversationID]
			if packet == nil || packet.EndSeq < 0 {
				return fmt.Errorf("invalid empty-preview visibility response for %q", conv.ConversationID)
			}
			if !packet.IsEnd {
				continue
			}
			r := pending[conv.ConversationID]
			if ascending {
				r[1] = min(r[1], packet.EndSeq)
			} else {
				r[0] = max(r[0], packet.EndSeq)
			}
			pending[conv.ConversationID] = r
		}
	}
	for id, r := range pending {
		original := visible[id]
		tail := batch[id][1]
		if r[0] <= tail && tail <= r[1] {
			continue // The missing preview is still readable, so proof is incomplete.
		}
		var invisible [][2]int64
		if r[0] > original[0] {
			invisible = append(invisible, [2]int64{original[0], min(original[1], r[0]-1)})
		}
		if r[1] < original[1] {
			invisible = append(invisible, [2]int64{max(original[0], r[1]+1), original[1]})
		}
		if len(invisible) > 0 {
			// Directional history proves these sequences are outside visibility.
			// Record only those ranges: a suffix must never acknowledge older holes.
			if err := m.commitMessageCoverage(ctx, id, invisible); err != nil {
				return err
			}
			messageSyncPageCommitted(ctx)
		}
		// Tightening the upper bound must not expand the automatic recent window
		// backwards into history which was deliberately left for on-demand reads.
		r[0] = max(r[0], original[1]-recentMessageWindow+1)
		visible[id] = r
		if m.syncedMaxSeqs[id] >= tail || m.messageAlreadyCovered(id, tail) {
			delete(batch, id)
			closed++
		}
	}
	log.ZInfo(ctx, "sync_diag empty_previews_revalidated", "candidates", len(pending), "confirmedInvisible", closed, "stillIncomplete", len(pending)-closed)
	return nil
}
