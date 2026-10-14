package interaction

import (
	"context"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/log"
)

const (
	cmdReconcileMessageSeq           = "reconcileMessageSeq"
	messageSeqReconciliationInterval = 30 * time.Second
)

// A healthy socket can miss its final push without ever exposing a sequence
// gap. Check the server watermark independently of pushes, through the same
// serial scheduler that owns all sequence mutations and storage commits.
func (m *MsgSyncer) listenWithReconciliation(ctx context.Context, ticks <-chan time.Time) {
	loopCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageSeqReconciliation(loopCtx, ticks, m.canReconcileMessageSeqs, m.recvCh)
	}()
	defer func() {
		cancel()
		<-done
	}()
	runMessageSyncLoop(loopCtx, m.recvCh, m.handlePushMsgAndEventSafely, func() bool { return m.reinstalled })
}

func runMessageSeqReconciliation(ctx context.Context, ticks <-chan time.Time, ready func() bool, input chan<- common.Cmd2Value) {
	for {
		select {
		case <-ctx.Done():
			return
		case _, ok := <-ticks:
			if !ok || ctx.Err() != nil {
				return
			}
			if !ready() {
				continue
			}
			// Busy queues already have work that can restore coverage. A later
			// tick retries; never let this maintenance task block logout or push.
			select {
			case input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdReconcileMessageSeq}:
			case <-ctx.Done():
				return
			default:
			}
		}
	}
}

func (m *MsgSyncer) canReconcileMessageSeqs() bool {
	return m.longConnMgr != nil && m.longConnMgr.IsConnected() && !m.longConnMgr.GetBackground()
}

func (m *MsgSyncer) doMessageSeqReconciliation(ctx context.Context) {
	// Recheck after queueing. Bootstrap needs its normal metadata sync, and a
	// foreground tick must not start new traffic once the app is backgrounded.
	if ctx.Err() != nil || !m.canReconcileMessageSeqs() {
		return
	}
	if m.reinstalled {
		// The persisted Installed=false state is also a retry obligation.
		// Re-enter required initialization, never the message-only shortcut.
		if m.startSync() {
			m.doConnected(ctx)
		}
		return
	}
	var resp sdkws.GetMaxSeqResp
	if err := m.longConnMgr.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{UserID: m.loginUserID}, constant.GetNewestSeq, &resp); err != nil {
		log.ZWarn(ctx, "message sequence reconciliation failed", err)
		return
	}
	if ctx.Err() != nil || !m.canReconcileMessageSeqs() {
		return
	}
	if err := m.compareSeqsAndBatchSync(ctx, resp.MaxSeqs, defaultPullNums); err != nil {
		// The next tick retries uncommitted ranges. Do not start a full
		// metadata sync or change the foreground sync indicator for a probe.
		log.ZWarn(ctx, "message sequence reconciliation pull failed", err)
	}
}
