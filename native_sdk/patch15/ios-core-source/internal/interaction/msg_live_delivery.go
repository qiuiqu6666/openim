package interaction

import (
	"context"
	"fmt"
	"sort"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func (m *MsgSyncer) recordDeliveredTail(ctx context.Context, id string, seq int64) error {
	state := m.checkpoints[id]
	if seq <= state.Delivered {
		return nil
	}
	state.Completed = m.syncedMaxSeqs[id]
	state.Target = max(state.Target, seq)
	state.Delivered = seq
	return m.saveMessageCheckpoint(ctx, id, state)
}

// A latest-page delivery is independent of the coverage checkpoint. Persisted
// message identity and the delivery journal make later full replay idempotent.
func (m *MsgSyncer) deliverRecentMessageTail(ctx context.Context, id string, r [2]int64) error {
	if IsNotification(id) || r[1]-r[0]+1 <= SplitPullMsgNum || m.checkpoints[id].Delivered >= r[1] {
		return nil
	}
	const latestPageSize int64 = 20
	r[0] = max(r[0], r[1]-latestPageSize+1)
	resp, err := m.pullMsgBySeqRange(ctx, map[string][2]int64{id: r}, latestPageSize)
	if err != nil {
		return err
	}
	if resp == nil || resp.Msgs[id] == nil {
		return fmt.Errorf("latest page missing conversation %q", id)
	}
	rows := resp.Msgs[id].Msgs
	seen := make(map[int64]bool)
	end := int64(0)
	for _, row := range rows {
		if row == nil || row.Seq < r[0] || row.Seq > r[1] || seen[row.Seq] {
			return fmt.Errorf("invalid latest page for %q", id)
		}
		seen[row.Seq] = true
		end = max(end, row.Seq)
	}
	if len(rows) == 0 {
		return nil
	} // Empty is not a deletion or a completed range.
	sort.Slice(rows, func(i, j int) bool { return rows[i].Seq < rows[j].Seq })
	err = common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: constant.CmdNewMsgCome,
		Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{id: {Msgs: rows}}, Recovery: true, ReconcileReadSeq: !m.recoveryReadSeqReady}}, m.conversationCh)
	if err != nil {
		return err
	}
	m.recoveryReadSeqReady = true
	return m.recordDeliveredTail(ctx, id, end)
}
