package open_im_sdk

import (
	"context"
	"errors"
	"sync"
)

// The slot is released by the worker after cleanup, never by its waiter.
type loginAttempt struct {
	mu        sync.Mutex
	id        string
	cancel    context.CancelFunc
	done      chan struct{}
	committed bool
}

func (a *loginAttempt) begin(parent context.Context, id string) (context.Context, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.done != nil {
		return nil, errors.New("login cleanup pending")
	}
	ctx, cancel := context.WithCancel(parent)
	a.id, a.cancel, a.done, a.committed = id, cancel, make(chan struct{}), false
	return ctx, nil
}

func (a *loginAttempt) commit(ctx context.Context, fn func()) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	fn()
	a.committed = true
	return nil
}

func (a *loginAttempt) finish() {
	a.mu.Lock()
	defer a.mu.Unlock()
	// A committed context belongs to the live session, not this attempt.
	if !a.committed {
		a.cancel()
	}
	close(a.done)
	a.done = nil
}

func (a *loginAttempt) cancelAndWait(ctx context.Context, id string) error {
	a.mu.Lock()
	if a.done == nil && a.id != id {
		a.mu.Unlock()
		return errors.New("login registration pending")
	}
	if a.done == nil || a.id != id || a.committed {
		a.mu.Unlock()
		return nil
	}
	a.cancel()
	done := a.done
	a.mu.Unlock()
	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
