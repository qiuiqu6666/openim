//go:build !js

package interaction

import (
	"context"
	"testing"
	"time"
)

func TestReconnectBackoffDoesNotWrapAndResetIsExplicit(t *testing.T) {
	r := NewExponentialRetry()
	for i := 0; i < 100; i++ {
		d := r.GetSleepInterval()
		if i >= 5 && (d < 15*time.Second || d > 30*time.Second) {
			t.Fatalf("sustained failure returned to fast retry: attempt=%d delay=%v", i, d)
		}
	}
	r.Reset()
	if d := r.GetSleepInterval(); d < 500*time.Millisecond || d > time.Second {
		t.Fatal(d)
	}
}

func TestRecoveryWaitCancelledAndWakeCoalesced(t *testing.T) {
	c := &LongConnMgr{}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if c.waitReconnect(ctx, time.Hour) {
		t.Fatal("cancelled session retried")
	}
	for i := 0; i < 1000; i++ {
		c.wakeReconnect()
	}
	if len(c.recoverySignal()) != 1 {
		t.Fatal("wake events not coalesced")
	}
	if !c.waitReconnect(context.Background(), time.Hour) {
		t.Fatal("wake ignored")
	}
	if len(c.recoverySignal()) != 0 {
		t.Fatal("wake not consumed")
	}
}

func TestForegroundInterruptsBackgroundBackoff(t *testing.T) {
	c := &LongConnMgr{}
	c.SetBackground(true)
	done := make(chan bool, 1)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	go func() { done <- c.waitReconnect(ctx, time.Minute) }()
	c.SetBackground(false)
	if !<-done {
		t.Fatal("foreground did not wake reconnect")
	}
}

func TestNativeDialHonorsSessionCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	d := NewWebSocket(0)
	_, err := dialSession(ctx, d, "ws://127.0.0.1:1")
	if err == nil || !d.IsNil() {
		t.Fatal("cancelled dial opened a socket")
	}
}
