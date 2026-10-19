//go:build !js

package db

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestGetMessagesBySeqsBeforeFirstCachedMessage(t *testing.T) {
	ctx := context.Background()
	store, err := NewDataBase(ctx, "cold-receipt", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close(ctx) })
	for _, id := range []string{"sg_@lg_cold_receipt", "si_cold_receipt"} {
		for attempt := 0; attempt < 2; attempt++ {
			rows, err := store.GetMessagesBySeqs(ctx, id, []int64{1, 2})
			if err != nil || len(rows) != 0 {
				t.Fatalf("empty cache receipt attempt %d: rows=%v err=%v", attempt, rows, err)
			}
		}
		if err := store.BatchInsertMessageList(ctx, id, []*model_struct.LocalChatLog{
			{ClientMsgID: "one", Seq: 1, SendTime: 10},
			{ClientMsgID: "two", Seq: 2, SendTime: 20},
		}); err != nil {
			t.Fatal(err)
		}
		rows, err := store.GetMessagesBySeqs(ctx, id, []int64{2, 99})
		if err != nil || len(rows) != 1 || rows[0].ClientMsgID != "two" {
			t.Fatalf("cached receipt lookup: rows=%v err=%v", rows, err)
		}
	}
}

func TestGetMessagesBySeqsRetainsStorageFailure(t *testing.T) {
	ctx := context.Background()
	store, err := NewDataBase(ctx, "failed-receipt", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.Close(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := store.GetMessagesBySeqs(ctx, "sg_closed", []int64{1}); err == nil {
		t.Fatal("a closed database must not be acknowledged as an empty cache")
	}
}
