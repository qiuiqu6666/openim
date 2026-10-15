//go:build cgo && !js

package db

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestInitialNotificationBootstrapRetryIsMonotonic(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	d, err := NewDataBase(ctx, "bootstrap-retry", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(ctx) })
	write := func(rows ...*model_struct.NotificationSeqs) {
		t.Helper()
		if err := d.BatchInsertNotificationSeq(ctx, rows); err != nil {
			t.Fatal(err)
		}
	}
	write(&model_struct.NotificationSeqs{ConversationID: "n_first", Seq: 7})
	// A message pull failed after the notification baseline committed. The
	// next initial-sync attempt must survive the already persisted baseline.
	write(&model_struct.NotificationSeqs{ConversationID: "n_first", Seq: 7})
	if err := d.Close(ctx); err != nil {
		t.Fatal(err)
	}
	d, err = NewDataBase(ctx, "bootstrap-retry", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	// A stale response cannot move backwards; a newer bootstrap observation
	// and an unseen conversation are committed together.
	write(&model_struct.NotificationSeqs{ConversationID: "n_first", Seq: 3},
		&model_struct.NotificationSeqs{ConversationID: "n_second", Seq: 2})
	write(&model_struct.NotificationSeqs{ConversationID: "n_first", Seq: 9})
	rows, err := d.GetNotificationAllSeqs(ctx)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]int64{}
	for _, row := range rows {
		got[row.ConversationID] = row.Seq
	}
	if len(rows) != 2 || got["n_first"] != 9 || got["n_second"] != 2 {
		t.Fatalf("notification retry corrupted baseline: %+v", got)
	}
	write()
}
