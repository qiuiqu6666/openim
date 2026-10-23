package interaction

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

// A historical hole is not a missing recent window. Use only persisted coverage
// to skip work; never advance the contiguous checkpoint or suppress notifications.
// Any uncovered recent sequence still takes the existing visibility/proof path.
func (m *MsgSyncer) pendingRecentRecoveryRanges(ranges map[string][2]int64) map[string][2]int64 {
	var pending map[string][2]int64
	for id, r := range ranges {
		if !IsNotification(id) && m.checkpoints[id].persisted && len(m.recentMissingRanges(id, r)) == 0 {
			continue
		}
		if pending == nil {
			pending = make(map[string][2]int64)
		}
		pending[id] = r
	}
	return pending
}

func (m *MsgSyncer) finishRecoveryReadReconciliation(ctx context.Context, reinstall bool) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	// Out-of-order live rows may close the whole latest window before the
	// recovery job runs. Reconcile unread even when no message page is missing.
	if m.pendingReadReconcile && !reinstall {
		if !m.recoveryReadSeqReady {
			if err := common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: constant.CmdNewMsgCome, Value: sdk_struct.CmdNewMsgComeToConversation{ReconcileReadSeq: true, Recovery: true}}, m.conversationCh); err != nil {
				return err
			}
		}
		m.pendingReadReconcile = false
	}
	return nil
}
