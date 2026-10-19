package interaction

import (
	"context"
	"time"
)

const messageSyncRetryMin = time.Second
const messageSyncRetryMax = 30 * time.Second

// Owned by the scheduler. Incoming pushes never wait on this clock and never
// reset it; only a completed recovery attempt can demonstrate progress.
type messageSyncRetry struct {
	delay time.Duration
	next  time.Time
}

func (r *messageSyncRetry) failed(now time.Time, progressed bool) {
	if progressed {
		r.delay = 0
	}
	if r.delay == 0 {
		r.delay = messageSyncRetryMin
	} else {
		r.delay = min(messageSyncRetryMax, r.delay*2)
	}
	r.next = now.Add(r.delay)
}

func (r *messageSyncRetry) remaining(now time.Time) time.Duration {
	return max(time.Duration(0), r.next.Sub(now))
}

func recordMessageSyncFailure(ctx context.Context, err error) {
	if err == nil || ctx.Err() != nil {
		return // Scheduler preemption and logout are not failed recovery attempts.
	}
	if owner, ok := ctx.Value(messagePageContextKey{}).(*messagePageCoordinator); ok {
		owner.failed.Store(true)
	}
}
