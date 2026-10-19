package common

import (
	"context"
	"errors"
	"testing"
	"time"
)

type yieldingTestWorker struct {
	queue   chan Cmd2Value
	started chan struct{}
	updated chan struct{}
}

func (w *yieldingTestWorker) GetCh() chan Cmd2Value                   { return w.queue }
func (w *yieldingTestWorker) InterruptibleCommand(cmd Cmd2Value) bool { return cmd.Cmd == "sync" }
func (w *yieldingTestWorker) Work(cmd Cmd2Value) {
	if cmd.Cmd == "sync" {
		close(w.started)
		<-cmd.Ctx.Done()
		cmd.Receipt <- cmd.Ctx.Err()
	} else {
		close(w.updated)
	}
}
func TestSentConversationUpdateInterruptsMetadataWait(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &yieldingTestWorker{make(chan Cmd2Value, 2), make(chan struct{}), make(chan struct{})}
	done := make(chan struct{})
	go func() { defer close(done); DoListener(ctx, w) }()
	receipt := make(chan error, 1)
	w.queue <- Cmd2Value{Ctx: ctx, Cmd: "sync", Receipt: receipt}
	<-w.started
	w.queue <- Cmd2Value{Ctx: ctx, Cmd: "sent-message-update"}
	select {
	case <-w.updated:
	case <-time.After(time.Second):
		t.Fatal("sent message update blocked by sync")
	}
	if err := <-receipt; !errors.Is(err, context.Canceled) {
		t.Fatalf("sync falsely succeeded: %v", err)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("listener leaked on logout")
	}
}

type selfNotifyingWorker struct {
	queue     chan Cmd2Value
	generated chan struct{}
	finish    chan struct{}
	updated   chan error
}

type bootstrapWorker struct{ *selfNotifyingWorker }

func (w *bootstrapWorker) ProtectSyncCommand(cmd Cmd2Value) bool { return cmd.Cmd == "sync" }

func TestBootstrapDrainsButDoesNotYieldToExternalUpdates(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &bootstrapWorker{&selfNotifyingWorker{make(chan Cmd2Value, 4), make(chan struct{}), make(chan struct{}), make(chan error, 2)}}
	done := make(chan struct{})
	go func() { defer close(done); DoListener(ctx, w) }()
	receipt := make(chan error, 1)
	w.queue <- Cmd2Value{Cmd: "sync", Ctx: ctx, Receipt: receipt}
	<-w.generated
	w.queue <- Cmd2Value{Cmd: "external-live-update", Ctx: ctx}
	select {
	case err := <-receipt:
		t.Fatalf("bootstrap interrupted by live traffic: %v", err)
	case <-w.updated:
		t.Fatal("message handled without bootstrap data")
	case <-time.After(30 * time.Millisecond):
	}
	close(w.finish)
	if err := <-receipt; err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		select {
		case err := <-w.updated:
			if err != nil {
				t.Fatal(err)
			}
		case <-time.After(time.Second):
			t.Fatal("queued update lost")
		}
	}
	cancel()
	<-done
}

func (w *selfNotifyingWorker) GetCh() chan Cmd2Value                   { return w.queue }
func (w *selfNotifyingWorker) InterruptibleCommand(cmd Cmd2Value) bool { return cmd.Cmd == "sync" }
func (w *selfNotifyingWorker) Work(cmd Cmd2Value) {
	if cmd.Cmd != "sync" {
		w.updated <- cmd.Ctx.Err()
		return
	}
	w.queue <- Cmd2Value{Cmd: "profile-update", Ctx: cmd.Ctx}
	close(w.generated)
	select {
	case <-cmd.Ctx.Done():
		cmd.Receipt <- cmd.Ctx.Err()
	case <-w.finish:
		cmd.Receipt <- nil
	}
}

func TestMetadataNotificationsDoNotRestartTheirOwnSync(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &selfNotifyingWorker{make(chan Cmd2Value, 4), make(chan struct{}), make(chan struct{}), make(chan error, 1)}
	done := make(chan struct{})
	go func() { defer close(done); DoListener(ctx, w) }()
	receipt := make(chan error, 1)
	w.queue <- Cmd2Value{Cmd: "sync", Ctx: ctx, Receipt: receipt}
	<-w.generated
	select {
	case err := <-receipt:
		t.Fatalf("sync cancelled by its own metadata notification: %v", err)
	case <-w.updated:
		t.Fatal("metadata applied concurrently with active sync")
	case <-time.After(30 * time.Millisecond):
	}
	close(w.finish)
	select {
	case err := <-receipt:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("sync did not complete")
	}
	select {
	case err := <-w.updated:
		if err != nil {
			t.Fatalf("metadata notification lost after cleanup: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("metadata notification not delivered")
	}
	cancel()
	<-done
}

func TestShortMetadataCompletesBeforePreemptionGrace(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &selfNotifyingWorker{make(chan Cmd2Value, 4), make(chan struct{}), make(chan struct{}), make(chan error, 2)}
	done := make(chan struct{})
	go func() { defer close(done); DoListener(ctx, w) }()
	receipt := make(chan error, 1)
	w.queue <- Cmd2Value{Ctx: ctx, Cmd: "sync", Receipt: receipt}
	<-w.generated
	w.queue <- Cmd2Value{Ctx: ctx, Cmd: "external-live-update"}
	time.Sleep(10 * time.Millisecond)
	close(w.finish)
	select {
	case err := <-receipt:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("sync blocked")
	}
	cancel()
	<-done
}
