package logpolicy

import (
	"sync"
	"testing"
	"time"
)

func TestDiagnosticWindowExpiryDisableAndRenewal(t *testing.T) {
	var w window
	now := time.Now()
	if w.remaining(now) != 0 {
		t.Fatal("diagnostics enabled by default")
	}
	if w.configure(60, now) != 60 || w.remaining(now) != 60 {
		t.Fatal("enable failed")
	}
	if w.remaining(now.Add(59999*time.Millisecond)) != 1 || w.remaining(now.Add(time.Minute)) != 0 {
		t.Fatal("expiry boundary failed")
	}
	// Renewing cannot be cancelled by an older window's expiry.
	w.configure(120, now.Add(30*time.Second))
	if w.remaining(now.Add(time.Minute)) != 90 {
		t.Fatal("renewal lost")
	}
	w.configure(0, now)
	if w.remaining(now) != 0 {
		t.Fatal("disable failed")
	}
	w.configure(-1, now)
	if w.remaining(now) != 0 {
		t.Fatal("negative duration enabled diagnostics")
	}
	if w.configure(int(^uint(0)>>1), now) != MaxDiagnosticSeconds || w.remaining(now) != MaxDiagnosticSeconds {
		t.Fatal("duration cap failed")
	}
}
func TestSuccessPolicyRetainsSlowCalls(t *testing.T) {
	Configure(0)
	t.Cleanup(func() { Configure(0) })
	if LogSuccess(time.Millisecond) || !LogSuccess(SlowCallThreshold) {
		t.Fatal("compact policy failed")
	}
	Configure(30)
	if !LogSuccess(time.Millisecond) {
		t.Fatal("detailed policy failed")
	}
	Configure(0)
	if LogSuccess(time.Millisecond) {
		t.Fatal("disable failed")
	}
}
func TestConcurrentDiagnosticWindow(t *testing.T) {
	var w window
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 1000; j++ {
				w.configure(j%901, time.Now())
				n := w.remaining(time.Now())
				if n < 0 || n > MaxDiagnosticSeconds {
					t.Errorf("remaining=%d", n)
				}
			}
		}()
	}
	wg.Wait()
}
