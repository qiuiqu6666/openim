package interaction

import (
	"context"
	"fmt"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
)

// Resolve only from an explicit directional boundary on the existing history
// protocol. An empty range pull alone never proves deletion or visibility.
func (m *MsgSyncer) refreshVisibleMessageRange(ctx context.Context, id string, r [2]int64) ([2]int64, error) {
	return m.longConnMgr.ResolveVisibleMessageRange(ctx, m.loginUserID, id, r)
}

// ResolveVisibleMessageRange revalidates a conflicting cached bound using the
// existing directional history protocol. It does not change local checkpoints.
func (c *LongConnMgr) ResolveVisibleMessageRange(ctx context.Context, userID, id string, r [2]int64) ([2]int64, error) {
	for _, ascending := range []bool{false, true} {
		seq, order := r[0], sdkws.PullOrder_PullOrderDesc
		if ascending {
			seq, order = r[1], sdkws.PullOrder_PullOrderAsc
		}
		var resp msg.GetSeqMessageResp
		req := &msg.GetSeqMessageReq{UserID: userID, Order: order, Conversations: []*msg.ConversationSeqs{{ConversationID: id, Seqs: []int64{seq}}}}
		if err := c.SendReqWaitResp(ctx, req, constant.PullMsgBySeqList, &resp); err != nil {
			return r, err
		}
		rows := resp.Msgs[id]
		if rows == nil {
			return r, fmt.Errorf("visibility response missing %q", id)
		}
		if rows.IsEnd {
			if rows.EndSeq < 0 {
				return r, fmt.Errorf("invalid visibility boundary for %q", id)
			}
			if ascending && rows.EndSeq < r[1] {
				r[1] = rows.EndSeq
			}
			if !ascending && rows.EndSeq > r[0] {
				r[0] = rows.EndSeq
			}
		}
		if r[0] > r[1] {
			break
		}
	}
	return r, nil
}
