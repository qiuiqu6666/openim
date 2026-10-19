//go:build !js

package db

import (
	"context"
	"database/sql"
	"testing"
)

func TestSyncConnectionsPreserveFullDurability(t *testing.T) {
	ctx := context.Background()
	d, err := NewDataBase(ctx, "durability", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	pool, err := d.conn.DB()
	if err != nil {
		t.Fatal(err)
	}
	// Hold all five connections at once: a PRAGMA on only the initial
	// connection must not accidentally pass this test.
	var connections []*sql.Conn
	defer func() {
		for _, c := range connections {
			c.Close()
		}
	}()
	for i := 0; i < 5; i++ {
		c, err := pool.Conn(ctx)
		if err != nil {
			t.Fatal(err)
		}
		connections = append(connections, c)
		var mode string
		var sync int
		if err := c.QueryRowContext(ctx, "PRAGMA journal_mode").Scan(&mode); err != nil {
			t.Fatal(err)
		}
		if err := c.QueryRowContext(ctx, "PRAGMA synchronous").Scan(&sync); err != nil {
			t.Fatal(err)
		}
		if mode != "wal" || sync != 2 {
			t.Fatalf("connection %d: mode=%s synchronous=%d", i, mode, sync)
		}
	}
}
