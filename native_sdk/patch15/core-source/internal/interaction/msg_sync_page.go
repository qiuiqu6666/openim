package interaction

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"sync/atomic"
	"time"
)

type messagePageContextKey struct{}

// Only the scheduler handles ingress. A range worker lends it ownership at a
// committed page boundary and remains paused until that turn is acknowledged.
type messagePageCoordinator struct {
	bounded   atomic.Bool
	committed atomic.Int64
	failed    atomic.Bool
	turns     chan chan struct{}
}

func messageSyncPageCommitted(ctx context.Context) {
	if owner, ok := ctx.Value(messagePageContextKey{}).(*messagePageCoordinator); ok {
		owner.committed.Add(1)
	}
}

func protectMessagePages(ctx context.Context) func() {
	if owner, ok := ctx.Value(messagePageContextKey{}).(*messagePageCoordinator); ok {
		owner.bounded.Store(true)
		return func() { owner.bounded.Store(false) }
	}
	return func() {}
}

func yieldMessageSyncPage(ctx context.Context) error {
	owner, ok := ctx.Value(messagePageContextKey{}).(*messagePageCoordinator)
	if !ok {
		return ctx.Err()
	}
	started := time.Now()
	defer func() { common.RecordSyncMetric(ctx, "sync_page_queue_wait", 1, time.Since(started)) }()
	resume := make(chan struct{})
	select {
	case owner.turns <- resume:
	case <-ctx.Done():
		return ctx.Err()
	}
	select {
	case <-resume:
		return ctx.Err()
	case <-ctx.Done():
		return ctx.Err()
	}
}
