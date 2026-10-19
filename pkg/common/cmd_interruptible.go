package common

import (
	"context"
	"time"
)

type syncNotificationOwnerKey struct{}
type syncNotificationOwner struct{ marker bool }

// Only explicitly opted-in network sync commands can yield. Their original
// receipt reports cancellation, so the caller must retry rather than publish
// a false sync success. Normal message writes never overlap or get preempted.
func runInterruptibleListener(ctx context.Context, worker goroutine, interruptible func(Cmd2Value) bool) {
	var done chan struct{}
	var cancel context.CancelFunc
	var activeCtx context.Context
	owner := &syncNotificationOwner{}
	var pending []Cmd2Value
	protected := false
	var grace *time.Timer
	var graceDone <-chan time.Time
	stop := func() {
		if grace != nil {
			grace.Stop()
			grace = nil
			graceDone = nil
		}
		if cancel != nil {
			cancel()
			// A cancelled metadata job may still be waiting for a lock held by
			// an API call that publishes to this queue. Keep draining until the
			// job exits, but never apply updates concurrently with that job.
			queue := worker.GetCh()
		joining:
			for {
				select {
				case <-done:
					break joining
				case cmd, ok := <-queue:
					if !ok {
						queue = nil
						continue
					}
					if cmd.Ctx != nil && cmd.Ctx.Value(syncNotificationOwnerKey{}) == owner {
						cmd.Ctx = ctx
					}
					pending = append(pending, cmd)
				}
			}
			cancel, done = nil, nil
		}
	}
	defer stop()
	for {
		if ctx.Err() != nil {
			return
		}
		var cmd Cmd2Value
		if done == nil && len(pending) > 0 {
			cmd = pending[0]
			pending[0] = Cmd2Value{}
			pending = pending[1:]
		} else {
			select {
			case <-ctx.Done():
				return
			case <-graceDone:
				if delay := MetadataPreemptionDelay(activeCtx); delay > 0 {
					grace.Reset(delay)
					continue
				}
				stop()
				continue
			case <-done:
				stop()
				continue
			case value, ok := <-worker.GetCh():
				if !ok {
					return
				}
				cmd = value
			}
		}
		// Metadata synchronization emits its own profile/conversation updates.
		// Those are consequences of this job, not live traffic that should
		// cancel it. Apply them serially after it exits, on the login context.
		if cmd.Ctx != nil && cmd.Ctx.Value(syncNotificationOwnerKey{}) == owner {
			cmd.Ctx = ctx
			if done != nil {
				pending = append(pending, cmd)
			} else {
				runCommandSafely(worker, cmd)
			}
			continue
		}
		if done != nil {
			pending = append(pending, cmd)
			if !protected && grace == nil {
				grace = time.NewTimer(100 * time.Millisecond)
				graceDone = grace.C
			}
			continue
		}
		if !interruptible(cmd) {
			runCommandSafely(worker, cmd)
			continue
		}
		if cmd.Ctx == nil {
			cmd.Ctx = ctx
		}
		protected = false
		if policy, ok := worker.(interface{ ProtectSyncCommand(Cmd2Value) bool }); ok {
			protected = policy.ProtectSyncCommand(cmd)
		}
		attemptCtx, attemptCancel := context.WithCancel(context.WithValue(cmd.Ctx, syncNotificationOwnerKey{}, owner))
		cmd.Ctx, cancel = attemptCtx, attemptCancel
		activeCtx = attemptCtx
		done = make(chan struct{})
		go func(command Cmd2Value, finished chan struct{}) {
			defer close(finished)
			defer attemptCancel()
			runCommandSafely(worker, command)
		}(cmd, done)
		// Live work can already be buffered behind a protected bootstrap.
		// Do not make it wait for a newly started metadata retry to finish.
		if !protected && len(pending) > 0 {
			stop()
		}
	}
}
