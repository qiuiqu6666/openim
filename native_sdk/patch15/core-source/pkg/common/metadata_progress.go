package common

import (
	"context"
	"sync"
	"sync/atomic"
	"time"
)

type metadataProgressKey struct{}

// MetadataProgress belongs to one pending auxiliary recovery obligation. It
// survives attempts, never a new recovery or login. The owner joins all stages
// before retrying; the mutex protects independent parallel stage completions.
type MetadataProgress struct {
	mu          sync.Mutex
	completed   map[string]time.Time
	items       map[string]map[string]bool
	checkpoints atomic.Int64
}

// PendingMetadataItems retains per-entity progress until a whole sweep succeeds.
// Unlike stage freshness, a long sweep must not expire its completed prefix.
func PendingMetadataItems(ctx context.Context, scope string, ids []string) []string {
	p, _ := ctx.Value(metadataProgressKey{}).(*MetadataProgress)
	if p == nil {
		return ids
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	pending := make([]string, 0, len(ids))
	for _, id := range ids {
		if !p.items[scope][id] {
			pending = append(pending, id)
		}
	}
	return pending
}

// CompleteMetadataItem is called only after all entity writes succeed, or a
// successful endpoint response confirms the entity is unchanged.
func CompleteMetadataItem(ctx context.Context, scope, id string) {
	if ctx.Err() != nil {
		return
	}
	p, _ := ctx.Value(metadataProgressKey{}).(*MetadataProgress)
	if p == nil {
		return
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.items == nil {
		p.items = make(map[string]map[string]bool)
	}
	if p.items[scope] == nil {
		p.items[scope] = make(map[string]bool)
	}
	if !p.items[scope][id] {
		p.items[scope][id] = true
		p.checkpoints.Add(1)
	}
}

func FinishMetadataItems(ctx context.Context, scope string) {
	if p, _ := ctx.Value(metadataProgressKey{}).(*MetadataProgress); p != nil {
		p.mu.Lock()
		delete(p.items, scope)
		p.mu.Unlock()
	}
}

func WithMetadataProgress(ctx context.Context, progress *MetadataProgress) context.Context {
	return context.WithValue(ctx, metadataProgressKey{}, progress)
}

func RunMetadataStage(ctx context.Context, name string, run func(context.Context) error) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	progress, _ := ctx.Value(metadataProgressKey{}).(*MetadataProgress)
	if progress == nil {
		return run(ctx)
	}
	progress.mu.Lock()
	completedAt := progress.completed[name]
	progress.mu.Unlock()
	// A long-lived failing stage must not freeze the other profiles forever.
	if !completedAt.IsZero() && time.Since(completedAt) < time.Minute {
		return nil
	}
	if err := run(ctx); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	progress.mu.Lock()
	if progress.completed == nil {
		progress.completed = make(map[string]time.Time)
	}
	progress.completed[name] = time.Now()
	progress.checkpoints.Add(1)
	progress.mu.Unlock()
	return nil
}

// RecordMetadataCheckpoint counts committed batches, not requests or bytes.
func RecordMetadataCheckpoint(ctx context.Context) {
	if progress, _ := ctx.Value(metadataProgressKey{}).(*MetadataProgress); progress != nil {
		progress.checkpoints.Add(1)
	}
}

func (p *MetadataProgress) Checkpoints() int64 {
	if p == nil {
		return 0
	}
	return p.checkpoints.Load()
}

// MetadataRecoveryProgress identifies one resumable sweep, not a retry attempt.
func MetadataRecoveryProgress(ctx context.Context) *MetadataProgress {
	p, _ := ctx.Value(metadataProgressKey{}).(*MetadataProgress)
	return p
}
