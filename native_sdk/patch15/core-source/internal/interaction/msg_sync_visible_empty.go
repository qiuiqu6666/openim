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
		if r[0] <= r[1] {
			continue
		}
		// Only a confirmed invisible prefix can advance the contiguous cursor.
		// A reduced upper bound alone must not acknowledge unseen older rows.
		if r[0] > visible[id][1] {
			if err := m.commitMessageCheckpoint(ctx, id, visible[id][1]); err != nil {
				return err
			}
		} else {
			continue
		}
		visible[id] = r
		delete(batch, id)
		closed++
	}
	log.ZInfo(ctx, "sync_diag empty_previews_revalidated", "candidates", len(pending), "confirmedInvisible", closed, "stillIncomplete", len(pending)-closed)
	return nil
}
