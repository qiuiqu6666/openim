package interaction

import (
	"context"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

func isBackgroundSyncCommand(cmd common.Cmd2Value) bool {
	return cmd.Cmd == constant.CmdConnSuccesss ||
		cmd.Cmd == constant.CmdWakeUpDataSync || cmd.Cmd == constant.CmdIMMessageSync ||
		cmd.Cmd == cmdReconcileMessageSeq || cmd.Cmd == cmdSyncAuxiliaryMetadata
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
	case cmdSyncAuxiliaryMetadata:
		return 0
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
	const liveBurst = 32
	liveHandled := 0
	var pageOwner *messagePageCoordinator
	var pageTurns <-chan chan struct{}
	var preemption *time.Timer
	var preempt <-chan time.Time
	reserveProgress := false
	var retry messageSyncRetry
	var retryTimer *time.Timer
	var retryWake <-chan time.Time
	clearRetryTimer := func() {
		if retryTimer != nil {
			retryTimer.Stop()
		}
		retryTimer, retryWake = nil, nil
	}
	defer clearRetryTimer()
	clearPreemption := func() {
		if preemption != nil {
			preemption.Stop()
		}
		preemption, preempt = nil, nil
	}
	stop := func() {
		clearPreemption()
		if cancel != nil {
			cancel()
			<-done // The sole state owner must exit before another command runs.
			// A live push can win the select just as a failed worker exits.
			// Preserve its failure here too, so traffic cannot bypass the cooldown.
			if pageOwner.failed.Load() {
				retry.failed(time.Now(), pageOwner.committed.Load() > 0)
				pending = coalesceMessageSync(pending, *active)
			}
			cancel, done, active = nil, nil, nil
			pageOwner, pageTurns = nil, nil
		}
	}
	defer stop()
	for {
		if ctx.Err() != nil {
			return
		}
		if active == nil && len(queued) > 0 && (pending == nil || liveHandled < liveBurst || retry.remaining(time.Now()) > 0) {
			cmd := queued[0]
			queued[0] = common.Cmd2Value{}
			queued = queued[1:]
			handle(cmd)
			liveHandled++
			continue
		}
		// Drain already queued work before restarting an interrupted sync.
		if active == nil && pending != nil && retry.remaining(time.Now()) == 0 {
			clearRetryTimer()
			protected = len(protectInitialSync) > 0 && protectInitialSync[0]()
			if !protected && liveHandled < liveBurst {
				select {
				case cmd, ok := <-input:
					if !ok {
						return
					}
					if isBackgroundSyncCommand(cmd) {
						pending = coalesceMessageSync(pending, cmd)
					} else {
						handle(cmd)
						liveHandled++
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
			pageOwner = &messagePageCoordinator{turns: make(chan chan struct{})}
			pageTurns = pageOwner.turns
			attempt.Ctx, cancel = context.WithValue(attemptCtx, messagePageContextKey{}, pageOwner), attemptCancel
			liveHandled = 0
			done = make(chan struct{})
			go func(finished chan struct{}) {
				defer close(finished)
				defer attemptCancel()
				handle(attempt)
			}(done)
		}
		if active == nil && pending != nil && retryTimer == nil {
			retryTimer = time.NewTimer(retry.remaining(time.Now()))
			retryWake = retryTimer.C
		}
		select {
		case <-ctx.Done():
			return
		case <-retryWake:
			clearRetryTimer()
		case <-done:
			if !pageOwner.failed.Load() {
				retry = messageSyncRetry{}
			}
			reserveProgress = false
			stop()
		case <-preempt:
			// A stalled first attempt may yield once. Its retry owns a bounded
			// page until completion, so busy chats cannot cancel it forever.
			if active != nil {
				resume := *active
				pending = coalesceMessageSync(pending, resume)
				reserveProgress = true
				stop()
			}
		case resume := <-pageTurns:
			clearPreemption()
			if pageOwner.committed.Load() > 0 {
				reserveProgress = false
			}
			// The worker is paused and no message transaction is in flight.
			// Bound the ingress turn so continuous traffic cannot starve pages.
			for n := 0; n < liveBurst; n++ {
				var cmd common.Cmd2Value
				if len(queued) > 0 {
					cmd, queued = queued[0], queued[1:]
				} else {
					select {
					case incoming, ok := <-input:
						if !ok {
							close(resume)
							return
						}
						cmd = incoming
					default:
						n = liveBurst
						continue
					}
				}
				if isBackgroundSyncCommand(cmd) {
					pending = coalesceMessageSync(pending, cmd)
				} else {
					handle(cmd)
				}
			}
			close(resume)
		case cmd, ok := <-input:
			if !ok {
				return
			}
			if isBackgroundSyncCommand(cmd) {
				if cmd.Cmd == constant.CmdConnSuccesss {
					// A fresh transport may recover a network failure immediately.
					retry = messageSyncRetry{}
					clearRetryTimer()
				}
				// Repeated foreground/reconnect signals describe the same desired
				// catch-up. Do not accumulate full sync jobs behind live traffic.
				if active == nil || cmd.Cmd == constant.CmdConnSuccesss || cmd.Cmd == cmdSyncAuxiliaryMetadata ||
					(active.Cmd == cmdReconcileMessageSeq && messageSyncPriority(cmd.Cmd) > 1) {
					pending = coalesceMessageSync(pending, cmd)
				}
				if active != nil && active.Cmd == cmdReconcileMessageSeq && messageSyncPriority(cmd.Cmd) > 1 {
					stop()
				}
				continue
			}
			if active != nil {
				if protected || reserveProgress || (pageOwner != nil && pageOwner.bounded.Load()) {
					queued = append(queued, cmd)
					if !protected && !reserveProgress && preemption == nil {
						preemption = time.NewTimer(100 * time.Millisecond)
						preempt = preemption.C
					}
					continue
				}
				resume := *active
				if pending == nil {
					pending = &resume
				}
				// Metadata/max-sequence I/O must also get an uninterrupted retry.
				reserveProgress = true
				stop()
			}
			handle(cmd)
		}
	}
}
