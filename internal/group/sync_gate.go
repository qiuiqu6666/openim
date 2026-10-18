package group

import (
	"context"
	"sync"
)

// Keep API writes and recovery serialized, but let cancelled recovery leave
// the wait queue without waiting for an unrelated API's network operation.
type groupSyncGate struct {
	once  sync.Once
	token chan struct{}
}

func (g *groupSyncGate) LockContext(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	g.once.Do(func() { g.token = make(chan struct{}, 1) })
	select {
	case <-ctx.Done():
		return ctx.Err()
	case g.token <- struct{}{}:
		if err := ctx.Err(); err != nil {
			g.Unlock()
			return err
		}
		return nil
	}
}
func (g *groupSyncGate) Lock()   { _ = g.LockContext(context.Background()) }
func (g *groupSyncGate) Unlock() { <-g.token }
