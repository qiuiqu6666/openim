package common

import (
	"context"
	"testing"
	"time"
)

type pendingRetryWorker struct {
	queue   chan Cmd2Value
	started chan struct{}
	finish  chan struct{}
	applied chan struct{}
}

func (w *pendingRetryWorker) GetCh() chan Cmd2Value                   { return w.queue }
func (w *pendingRetryWorker) InterruptibleCommand(cmd Cmd2Value) bool { return cmd.Cmd != "live" }
func (w *pendingRetryWorker) ProtectSyncCommand(cmd Cmd2Value) bool   { return cmd.Cmd == "bootstrap" }
func (w *pendingRetryWorker) Work(cmd Cmd2Value) {
	switch cmd.Cmd {
	case "bootstrap":
		close(w.started)
		select {
		case <-w.finish:
		case <-cmd.Ctx.Done():
		}
	case "retry":
		<-cmd.Ctx.Done()
	case "live":
		close(w.applied)
	}
}

func TestPendingLiveTrafficPreemptsPendingMetadataRetry(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &pendingRetryWorker{make(chan Cmd2Value), make(chan struct{}), make(chan struct{}), make(chan struct{})}
	done := make(chan struct{})
	go func() { defer close(done); DoListener(ctx, w) }()
	w.queue <- Cmd2Value{Cmd: "bootstrap", Ctx: ctx}
	<-w.started
	// Unbuffered sends guarantee both items have reached pending before release.
	w.queue <- Cmd2Value{Cmd: "retry", Ctx: ctx}
	w.queue <- Cmd2Value{Cmd: "live", Ctx: ctx}
	close(w.finish)
	select {
	case <-w.applied:
	case <-time.After(time.Second):
		t.Error("pending live update trapped behind metadata retry")
	}
	cancel()
	<-done
}

func TestLogoutDrainsLockOwnerButDoesNotApplyOldAccountUpdates(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	w := &lockWaitingWorker{queue: make(chan Cmd2Value, 2), started: make(chan struct{}), cancelled: make(chan struct{}), applied: make(chan string, 10)}
	w.lock.Lock()
	done := make(chan struct{})
	go func() { defer close(done); DoListener(ctx, w) }()
	w.queue <- Cmd2Value{Cmd: "sync", Ctx: ctx, Receipt: make(chan error, 1)}
	<-w.started
	cancel()
	<-w.cancelled
	deadline := time.After(time.Second)
	for i := 0; i < 5; i++ {
		select {
		case w.queue <- Cmd2Value{Cmd: "old-account-update", Ctx: ctx}:
		case <-deadline:
			w.lock.Unlock()
			<-done
			t.Fatal("logout blocked group lock owner")
		}
	}
	w.lock.Unlock()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("logout listener leaked")
	}
	if len(w.applied) != 0 {
		t.Fatal("old account updates applied after logout")
	}
}
