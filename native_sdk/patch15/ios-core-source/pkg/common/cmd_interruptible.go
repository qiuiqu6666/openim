package common

import "context"

type syncNotificationOwnerKey struct{}
type syncNotificationOwner struct{ marker bool }

// Only explicitly opted-in network sync commands can yield. Their original
// receipt reports cancellation, so the caller must retry rather than publish
// a false sync success. Normal message writes never overlap or get preempted.
func runInterruptibleListener(ctx context.Context, worker goroutine, interruptible func(Cmd2Value) bool) {
	var done chan struct{}
	var cancel context.CancelFunc
	owner := &syncNotificationOwner{}
	var pending []Cmd2Value
	protected := false
	stop := func() {
		if cancel != nil {
			cancel()
			<-done
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
			if !protected {
				stop()
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
		done = make(chan struct{})
		go func(command Cmd2Value, finished chan struct{}) {
			defer close(finished)
			defer attemptCancel()
			runCommandSafely(worker, command)
		}(cmd, done)
	}
}
