package common

import (
	"context"
	"reflect"
)

type metadataStateKey struct {
	scope  string
	typeOf reflect.Type
}

// MetadataState retains typed work for one recovery obligation, never across
// logins. Callers serialize access to the returned state. Without an obligation,
// each call gets fresh state, so ordinary API calls cannot reuse old snapshots.
func MetadataState[T any](ctx context.Context, scope string) *T {
	p, _ := ctx.Value(metadataProgressKey{}).(*MetadataProgress)
	if p == nil {
		return new(T)
	}
	key := metadataStateKey{scope: scope, typeOf: reflect.TypeOf((*T)(nil))}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.states == nil {
		p.states = make(map[metadataStateKey]any)
	}
	if state, ok := p.states[key]; ok {
		return state.(*T)
	}
	state := new(T)
	p.states[key] = state
	return state
}
