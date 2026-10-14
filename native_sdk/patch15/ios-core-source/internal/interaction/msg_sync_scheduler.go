package interaction

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

func isBackgroundSyncCommand(cmd common.Cmd2Value) bool {
	return cmd.Cmd == constant.CmdConnSuccesss ||
		cmd.Cmd == constant.CmdWakeUpDataSync || cmd.Cmd == constant.CmdIMMessageSync ||
		cmd.Cmd == cmdReconcileMessageSeq
}

func coalesceMessageSync(pending *common.Cmd2Value, incoming common.Cmd2Value) *common.Cmd2Value {
	// Reconnect/foreground jobs also initialize metadata and publish the
	// normal sync lifecycle. Lightweight checks must not replace that work.
	if pending != nil && messageSyncPriority(incoming.Cmd) < messageSyncPriority(pending.Cmd) {
		return pending
	}
	return &incoming
}

func messageSyncPriority(cmd string) int {
	switch cmd {
	case constant.CmdConnSuccesss:
		return 4
	case constant.CmdWakeUpDataSync:
		return 3
	case constant.CmdIMMessageSync:
		return 2
	default:
		return 1
	}
}

// Yield slow sync I/O to live pushes, without concurrent sequence mutation or
// storage commits. A cancelled sync never advances uncommitted ranges; one
// coalesced sync command resumes after queued live messages have been handled.
func runMessageSyncLoop(ctx context.Context, input <-chan common.Cmd2Value, handle func(common.Cmd2Value), protectInitialSync ...func() bool) {
	var pending *common.Cmd2Value
	var active *common.Cmd2Value
	var done chan struct{}
	var cancel context.CancelFunc
	var queued []common.Cmd2Value
	protected := false
	stop := func() {
		if cancel != nil {
			cancel()
			<-done // The sole state owner must exit before another command runs.
			cancel, done, active = nil, nil, nil
		}
	}
	defer stop()
	for {
		if ctx.Err() != nil {
			return
		}
		if active == nil && len(queued) > 0 {
			cmd := queued[0]
			queued[0] = common.Cmd2Value{}
			queued = queued[1:]
			handle(cmd)
			continue
		}
		// Drain already queued work before restarting an interrupted sync.
		if active == nil && pending != nil {
			protected = len(protectInitialSync) > 0 && protectInitialSync[0]()
			if !protected {
				select {
				case cmd, ok := <-input:
					if !ok {
						return
					}
					if isBackgroundSyncCommand(cmd) {
						pending = coalesceMessageSync(pending, cmd)
					} else {
						handle(cmd)
					}
					continue
				default:
				}
			}
			original := *pending
			pending = nil
			if original.Ctx == nil {
				original.Ctx = ctx
			}
			if original.Ctx.Err() != nil {
				continue
			}
			active = &original
			// Read bootstrap state only while no job owns it. Once started,
			// first-login initialization cannot be starved by incoming traffic.
			attempt := original
			attemptCtx, attemptCancel := context.WithCancel(original.Ctx)
			attempt.Ctx, cancel = attemptCtx, attemptCancel
			done = make(chan struct{})
			go func(finished chan struct{}) {
				defer close(finished)
				defer attemptCancel()
				handle(attempt)
			}(done)
		}
		select {
		case <-ctx.Done():
			return
		case <-done:
			stop()
		case cmd, ok := <-input:
			if !ok {
				return
			}
			if isBackgroundSyncCommand(cmd) {
				// Repeated foreground/reconnect signals describe the same desired
				// catch-up. Do not accumulate full sync jobs behind live traffic.
				if active == nil || cmd.Cmd == constant.CmdConnSuccesss ||
					(active.Cmd == cmdReconcileMessageSeq && cmd.Cmd != cmdReconcileMessageSeq) {
					pending = coalesceMessageSync(pending, cmd)
				}
				if active != nil && active.Cmd == cmdReconcileMessageSeq && cmd.Cmd != cmdReconcileMessageSeq {
					stop()
				}
				continue
			}
			if active != nil {
				if protected {
					queued = append(queued, cmd)
					continue
				}
				resume := *active
				if pending == nil {
					pending = &resume
				}
				stop()
			}
			handle(cmd)
		}
	}
}
