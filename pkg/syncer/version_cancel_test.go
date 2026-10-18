package syncer

import (
	"context"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"testing"
)

func TestCancelledVersionSyncSkipsDatabaseAndServer(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	s := VersionSynchronizer[string, *int]{Ctx: ctx}
	if err := s.IncrementalSync(); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if err := s.CheckVersionSync(); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if err := s.updateVersionInfo(&model_struct.LocalVersionSync{}, nil); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
}

func TestCancellationAfterResponseDoesNotApplyOrCommit(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	db := &profileVersionDB{}
	s := VersionSynchronizer[string, *int]{Ctx: ctx, DB: db,
		ServerVersion: func() *int { cancel(); v := 1; return &v },
		Delete:        func(*int) []string { t.Error("processed cancelled response"); return nil },
	}
	if err := s.IncrementalSync(); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if db.saved != 0 {
		t.Fatal("cancelled version committed")
	}
}
