package interaction

import (
	"sync/atomic"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

func TestContiguousPushDoesNotRestartReadReconciliation(t *testing.T) {
	for _, id := range []string{"chat", "n_receipts"} {
		t.Run(id, func(t *testing.T) {
			ctx := recoveryContext(t)
			m := &MsgSyncer{ctx: ctx, conversationCh: make(chan common.Cmd2Value),
				syncedMaxSeqs: map[string]int64{id: 5}, recoveryReadSeqReady: true,
				pendingReadReconcile: true}
			var reconciliations atomic.Int32
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				if cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).ReconcileReadSeq {
					reconciliations.Add(1)
				}
				return nil
			})
			trigger := m.triggerConversation
			if IsNotification(id) {
				trigger = m.triggerNotification
			}
			for seq := int64(6); seq <= 15; seq++ {
				m.pushTriggerAndSync(ctx, recoveryMsgs(id, seq), trigger)
			}
			if reconciliations.Load() != 0 || !m.recoveryReadSeqReady || !m.pendingReadReconcile {
				t.Fatalf("contiguous pushes disturbed background recovery: scans=%d ready=%v pending=%v", reconciliations.Load(), m.recoveryReadSeqReady, m.pendingReadReconcile)
			}
			if m.syncedMaxSeqs[id] != 15 {
				t.Fatalf("push delivery did not advance: %d", m.syncedMaxSeqs[id])
			}
			// The background owner must still reconcile the obligation left by
			// a genuine earlier gap, even if live rows already closed that gap.
			if err := m.syncCompleteMessageRanges(ctx, nil, false); err != nil {
				t.Fatal(err)
			}
			if reconciliations.Load() != 1 || m.pendingReadReconcile {
				t.Fatalf("background reconciliation lost: scans=%d pending=%v", reconciliations.Load(), m.pendingReadReconcile)
			}
		})
	}
}
