package common

import (
	"context"
	"sync/atomic"
	"time"
)

type metadataTurnKey struct{}
type metadataTurn struct {
	deadline atomic.Int64
	active   atomic.Int64
}

// One shared allowance per attempt, across both message and conversation
// schedulers. Further batches cannot renew it and starve live messages.
const metadataTurnBudget = time.Second

func WithMetadataTurn(ctx context.Context) context.Context {
	return context.WithValue(ctx, metadataTurnKey{}, &metadataTurn{})
}

// Only bounded group batches opt in; unrelated or hung metadata still uses the
// normal 100ms grace. Parent cancellation/logout always bypasses this allowance.
func BeginMetadataBatch(ctx context.Context) func() {
	t, _ := ctx.Value(metadataTurnKey{}).(*metadataTurn)
	if t == nil {
		return func() {}
	}
	t.deadline.CompareAndSwap(0, time.Now().Add(metadataTurnBudget).UnixNano())
	t.active.Add(1)
	return func() { t.active.Add(-1) }
}

func MetadataPreemptionDelay(ctx context.Context) time.Duration {
	if ctx == nil || ctx.Err() != nil {
		return 0
	}
	t, _ := ctx.Value(metadataTurnKey{}).(*metadataTurn)
	if t == nil || t.active.Load() == 0 {
		return 0
	}
	remaining := time.Until(time.Unix(0, t.deadline.Load()))
	// Recheck at short intervals so completed work yields promptly. The absolute
	// deadline cannot be extended by a new batch or by the other scheduler.
	if remaining > 10*time.Millisecond {
		return 10 * time.Millisecond
	}
	if remaining < 0 {
		return 0
	}
	return remaining
}
