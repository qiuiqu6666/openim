package open_im_sdk

import (
	"context"
	"testing"
	"time"
)

func TestLoginCancelWaitsForCleanup(t *testing.T) {
	var a loginAttempt
	if a.cancelAndWait(context.Background(), "old") == nil {
		t.Fatal("unregistered worker acknowledged")
	}
	ctx, err := a.begin(context.Background(), "old")
	if err != nil {
		t.Fatal(err)
	}
	wait, cancel := context.WithTimeout(context.Background(), time.Millisecond)
	defer cancel()
	if a.cancelAndWait(wait, "old") == nil {
		t.Fatal("ack before cleanup")
	}
	if ctx.Err() == nil {
		t.Fatal("worker not cancelled")
	}
	if _, err := a.begin(context.Background(), "new"); err == nil {
		t.Fatal("overlapping login")
	}
	if a.commit(ctx, func() { t.Fatal("cancelled task committed") }) == nil {
		t.Fatal("commit accepted")
	}
	a.finish()
	if err := a.cancelAndWait(context.Background(), "old"); err != nil {
		t.Fatal(err)
	}
	next, err := a.begin(context.Background(), "new")
	if err != nil {
		t.Fatal(err)
	}
	if err := a.cancelAndWait(context.Background(), "old"); err != nil {
		t.Fatal(err)
	}
	if next.Err() != nil {
		t.Fatal("stale cancellation hit successor")
	}
	a.finish()
}

func TestLoginCommitWinsCancellation(t *testing.T) {
	var a loginAttempt
	ctx, _ := a.begin(context.Background(), "id")
	if err := a.commit(ctx, func() {}); err != nil {
		t.Fatal(err)
	}
	if err := a.cancelAndWait(context.Background(), "id"); err != nil {
		t.Fatal(err)
	}
	a.finish()
	if ctx.Err() != nil {
		t.Fatal("live session cancelled")
	}
}
