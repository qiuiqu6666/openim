package common

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestCancelledCommandNeverEnqueues(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	queue := make(chan Cmd2Value, 100)
	for i := 0; i < 100; i++ {
		if err := SendCmdWithReceipt(ctx, Cmd2Value{Cmd: "expired"}, queue); !errors.Is(err, context.Canceled) {
			t.Fatalf("got %v", err)
		}
	}
	if len(queue) != 0 {
		t.Fatalf("queued %d expired commands", len(queue))
	}
}

func TestReceiptWaitsForStorageAndReturnsFailure(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	queue := make(chan Cmd2Value, 1)
	done := make(chan error, 1)
	go func() { done <- SendCmdWithReceipt(ctx, Cmd2Value{Cmd: "store"}, queue) }()
	cmd := <-queue
	if cmd.ExpiresAt.IsZero() || time.Until(cmd.ExpiresAt) > time.Second {
		t.Fatal("queued command has no expiry")
	}
	select {
	case err := <-done:
		t.Fatalf("returned before storage: %v", err)
	default:
	}
	want := errors.New("disk full")
	cmd.Receipt <- want
	if err := <-done; !errors.Is(err, want) {
		t.Fatalf("got %v", err)
	}
	if cmd.Ctx.Err() != nil {
		t.Fatal("receipt cancelled follow-up work")
	}
}

func TestReceiptCancellationWithFullQueue(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	queue := make(chan Cmd2Value, 1)
	queue <- Cmd2Value{Cmd: "existing"}
	done := make(chan error, 1)
	go func() { done <- SendCmdWithReceipt(ctx, Cmd2Value{}, queue) }()
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("full queue ignored cancellation")
	}
}

type panicTestWorker struct {
	ch        chan Cmd2Value
	processed chan struct{}
}

func (w *panicTestWorker) GetCh() chan Cmd2Value { return w.ch }
func (w *panicTestWorker) Work(c Cmd2Value) {
	if c.Cmd == "panic" {
		panic("bad item")
	}
	w.processed <- struct{}{}
}

func TestListenerContinuesAfterPanicAndExitsOnClose(t *testing.T) {
	w := &panicTestWorker{make(chan Cmd2Value, 2), make(chan struct{}, 1)}
	w.ch <- Cmd2Value{Cmd: "panic", Ctx: context.Background()}
	w.ch <- Cmd2Value{Cmd: "next", Ctx: context.Background()}
	close(w.ch)
	done := make(chan struct{})
	go func() { DoListener(context.Background(), w); close(done) }()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("listener did not exit")
	}
	select {
	case <-w.processed:
	default:
		t.Fatal("panic stopped the receive worker")
	}
}
