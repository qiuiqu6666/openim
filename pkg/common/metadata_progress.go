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
	checkpoints atomic.Int64
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
