// Package logpolicy controls bounded, metadata-only SDK diagnostics.
package logpolicy

import (
	"sync/atomic"
	"time"
)

const MaxDiagnosticSeconds = 15 * 60
const SlowCallThreshold = time.Second

type window struct{ until atomic.Pointer[time.Time] }

var detailed window

func (w *window) configure(seconds int, now time.Time) int {
	if seconds <= 0 {
		w.until.Store(nil)
		return 0
	}
	if seconds > MaxDiagnosticSeconds {
		seconds = MaxDiagnosticSeconds
	}
	end := now.Add(time.Duration(seconds) * time.Second)
	w.until.Store(&end)
	return seconds
}
func (w *window) remaining(now time.Time) int {
	end := w.until.Load()
	if end == nil {
		return 0
	}
	left := end.Sub(now)
	if left <= 0 {
		return 0
	}
	return int((left + time.Second - 1) / time.Second)
}

// Configure enables diagnostics for a bounded window; nonpositive disables it.
// Nothing is persisted and no background timer or goroutine is created.
func Configure(seconds int) int             { return detailed.configure(seconds, time.Now()) }
func RemainingSeconds() int                 { return detailed.remaining(time.Now()) }
func Enabled() bool                         { return RemainingSeconds() > 0 }
func LogSuccess(elapsed time.Duration) bool { return elapsed >= SlowCallThreshold || Enabled() }
