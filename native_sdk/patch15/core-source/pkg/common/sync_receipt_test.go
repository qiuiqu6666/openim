package common

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestSyncReceiptContinuesWhileWorkProgresses(t *testing.T) {
	queue := make(chan Cmd2Value, 1)
	done := make(chan error, 1)
	go func() { done <- sendSyncCmdWithReceipt(context.Background(), Cmd2Value{}, queue, 200*time.Millisecond) }()
	cmd := <-queue
	if !cmd.ExpiresAt.IsZero() {
		t.Fatal("metadata still has a total deadline")
	}
	for i := 0; i < 8; i++ {
		time.Sleep(50 * time.Millisecond)
		ReportSyncProgress(cmd.Ctx)
		select {
		case err := <-done:
			t.Fatalf("active work expired: %v", err)
		default:
		}
	}
	want := errors.New("storage failure")
	cmd.Receipt <- want
	if err := <-done; !errors.Is(err, want) {
		t.Fatalf("lost worker result: %v", err)
	}
}

func TestSyncReceiptCancelsStalledWorker(t *testing.T) {
	queue := make(chan Cmd2Value, 1)
	done := make(chan error, 1)
	go func() { done <- sendSyncCmdWithReceipt(context.Background(), Cmd2Value{}, queue, 20*time.Millisecond) }()
	cmd := <-queue
	if err := <-done; !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	select {
	case <-cmd.Ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("stalled worker not cancelled")
	}
}

func TestSyncReceiptRespectsLogoutCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	queue := make(chan Cmd2Value, 1)
	done := make(chan error, 1)
	go func() { done <- SendSyncCmdWithReceipt(ctx, Cmd2Value{}, queue) }()
	cmd := <-queue
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if cmd.Ctx.Err() == nil {
		t.Fatal("worker outlived session")
	}
}
