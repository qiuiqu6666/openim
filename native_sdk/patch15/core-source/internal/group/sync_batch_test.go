package group

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
)

func TestGroupBatchCancellationStopsQueuedWork(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started := make(chan struct{}, 4)
	var calls atomic.Int32
	tasks := make([]func() error, 500)
	for i := range tasks {
		tasks[i] = func() error {
			calls.Add(1)
			started <- struct{}{}
			<-ctx.Done()
			return ctx.Err()
		}
	}
	done := make(chan error, 1)
	go func() { done <- runGroupSyncBatch(ctx, tasks) }()
	for i := 0; i < 4; i++ {
		<-started
	}
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if calls.Load() != 4 {
		t.Fatalf("started %d tasks after cancellation", calls.Load())
	}
}

func TestGroupBatchPreservesErrorAndProcessesRemainingGroups(t *testing.T) {
	failure := errors.New("profile failure")
	var calls atomic.Int32
	tasks := make([]func() error, 20)
	for i := range tasks {
		tasks[i] = func() error { calls.Add(1); return failure }
	}
	if err := runGroupSyncBatch(context.Background(), tasks); !errors.Is(err, failure) {
		t.Fatal(err)
	}
	if calls.Load() != 20 {
		t.Fatal(calls.Load())
	}
}

func TestGroupBatchAlreadyCancelledDoesNoWork(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := runGroupSyncBatch(ctx, []func() error{func() error { t.Error("cancelled task ran"); return nil }})
	if !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
}
