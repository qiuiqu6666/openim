package group

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestCancelledGroupRecoveryDoesNotWaitForAPILock(t *testing.T) {
	var gate groupSyncGate
	gate.Lock()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- gate.LockContext(ctx) }()
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled waiter blocked")
	}
	gate.Unlock()
	if err := gate.LockContext(context.Background()); err != nil {
		t.Fatal(err)
	}
	gate.Unlock()
}
