package common

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestMetadataProgressRetainsOnlySuccessfulStagesAcrossAttempts(t *testing.T) {
	progress := &MetadataProgress{}
	base := WithMetadataProgress(context.Background(), progress)
	first, cancel := context.WithCancel(base)
	completed, failed := 0, 0
	good := func(context.Context) error { completed++; return nil }
	bad := func(context.Context) error { failed++; return errors.New("network failure") }
	if err := RunMetadataStage(first, "user", good); err != nil {
		t.Fatal(err)
	}
	if err := RunMetadataStage(first, "friends", bad); err == nil {
		t.Fatal("lost failure")
	}
	cancel()
	if err := RunMetadataStage(first, "user", good); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if err := RunMetadataStage(base, "user", good); err != nil {
		t.Fatal(err)
	}
	_ = RunMetadataStage(base, "friends", bad)
	if completed != 1 || failed != 2 {
		t.Fatalf("completed=%d failed=%d", completed, failed)
	}
	// New obligation/session never inherits a previous completion.
	fresh := WithMetadataProgress(context.Background(), &MetadataProgress{})
	_ = RunMetadataStage(fresh, "user", good)
	if completed != 2 {
		t.Fatal("completion leaked to new recovery")
	}
}

func TestMetadataStageCancelledBeforeReturnIsNotCheckpointed(t *testing.T) {
	progress := &MetadataProgress{}
	base := WithMetadataProgress(context.Background(), progress)
	ctx, cancel := context.WithCancel(base)
	if err := RunMetadataStage(ctx, "friends", func(context.Context) error { cancel(); return nil }); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	called := false
	_ = RunMetadataStage(base, "friends", func(context.Context) error { called = true; return nil })
	if !called {
		t.Fatal("cancelled stage acknowledged")
	}
}

func TestLongMetadataOutageDoesNotFreezeSuccessfulProfiles(t *testing.T) {
	progress := &MetadataProgress{completed: map[string]time.Time{"user": time.Now().Add(-2 * time.Minute)}}
	ctx := WithMetadataProgress(context.Background(), progress)
	called := 0
	for i := 0; i < 2; i++ {
		if err := RunMetadataStage(ctx, "user", func(context.Context) error { called++; return nil }); err != nil {
			t.Fatal(err)
		}
	}
	if called != 1 {
		t.Fatalf("stale stage not refreshed once: %d", called)
	}
}
