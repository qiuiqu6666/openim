package common

import (
	"context"
	"github.com/openimsdk/tools/log"
	"sort"
	"sync"
	"time"
)

type syncMetricsKey struct{}
type SyncMetrics struct {
	mu               sync.Mutex
	started, emitted time.Time
	counts           map[string]int64
	durations        map[string][]float64
	totals           map[string]float64
}

// Metrics belong to one cancellable attempt, including its storage receipts.
// Event-driven output avoids a timer/goroutine per conversation. Samples are
// bounded; sums are task time, never presented as critical-path wall time.
func WithSyncMetrics(ctx context.Context) context.Context {
	now := time.Now()
	return context.WithValue(ctx, syncMetricsKey{}, &SyncMetrics{started: now, emitted: now, counts: map[string]int64{}, durations: map[string][]float64{}, totals: map[string]float64{}})
}

func RecordSyncMetric(ctx context.Context, name string, count int64, elapsed time.Duration) {
	if ctx == nil {
		return
	}
	m, _ := ctx.Value(syncMetricsKey{}).(*SyncMetrics)
	if m == nil {
		return
	}
	m.mu.Lock()
	m.counts[name] += count
	if elapsed > 0 {
		ms := float64(elapsed) / float64(time.Millisecond)
		m.totals[name] += ms
		samples := m.durations[name]
		if len(samples) < 4096 {
			samples = append(samples, ms)
		} else {
			samples[int(m.counts[name])%len(samples)] = ms
		}
		m.durations[name] = samples
	}
	due := time.Since(m.emitted) >= 10*time.Second
	m.mu.Unlock()
	if due {
		FlushSyncMetrics(ctx, false)
	}
}

func FlushSyncMetrics(ctx context.Context, final bool) {
	m, _ := ctx.Value(syncMetricsKey{}).(*SyncMetrics)
	if m == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if !final && time.Since(m.emitted) < 10*time.Second {
		return
	}
	m.emitted = time.Now()
	quantiles := map[string]map[string]float64{}
	for name, v := range m.durations {
		s := append([]float64(nil), v...)
		sort.Float64s(s)
		if len(s) > 0 {
			quantiles[name] = map[string]float64{"p50": s[(len(s)-1)*50/100], "p95": s[(len(s)-1)*95/100], "p99": s[(len(s)-1)*99/100], "sampleCount": float64(len(s))}
		}
	}
	log.ZInfo(ctx, "sync_perf aggregate", "wallMs", float64(time.Since(m.started))/float64(time.Millisecond), "counts", m.counts, "taskTotalMs", m.totals, "samplePercentilesMs", quantiles, "final", final, "cancelled", ctx.Err() != nil)
}
