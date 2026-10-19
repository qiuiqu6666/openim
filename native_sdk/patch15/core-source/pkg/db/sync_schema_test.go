//go:build !js

package db

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"testing"
)

func TestSyncSchemaFailureRollsBackAndCanRetry(t *testing.T) {
	ctx := context.Background()
	d, err := NewDataBase(ctx, "schema", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	if err := d.conn.Exec("CREATE TABLE conflict (seq INTEGER)").Error; err != nil {
		t.Fatal(err)
	}
	if err := d.conn.Exec("CREATE INDEX index_seq_chat ON conflict(seq)").Error; err != nil {
		t.Fatal(err)
	}
	if err := d.initChatLogs(ctx, []string{"chat", "other"}); err == nil {
		t.Fatal("expected index collision")
	}
	for _, id := range []string{"chat", "other"} {
		table := utils.GetTableName(id)
		if d.tableChecker.HasTable(table) || d.conn.Migrator().HasTable(table) {
			t.Fatalf("partial schema survived for %s", id)
		}
	}
	if err := d.conn.Exec("DROP INDEX index_seq_chat").Error; err != nil {
		t.Fatal(err)
	}
	if err := d.initChatLogs(ctx, []string{"chat", "other", "chat"}); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"chat", "other"} {
		table := utils.GetTableName(id)
		if !d.tableChecker.HasTable(table) || !d.conn.Migrator().HasTable(table) {
			t.Fatalf("retry lost %s", id)
		}
	}
}
