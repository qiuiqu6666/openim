package db

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestVersionHeadersPreserveMemberIDsAndScope(t *testing.T) {
	d, ctx := versionSyncTestDB(t)
	want := &model_struct.LocalVersionSync{Table: "members", EntityID: "g", VersionID: "v", Version: 9, UIDList: []string{"a", "b"}}
	if err := d.SetVersionSync(ctx, want); err != nil {
		t.Fatal(err)
	}
	if err := d.SetVersionSync(ctx, &model_struct.LocalVersionSync{Table: "other", EntityID: "g", Version: 77}); err != nil {
		t.Fatal(err)
	}
	rows, err := d.GetVersionSyncHeaders(ctx, "members", []string{"g", "missing"})
	if err != nil || len(rows) != 1 || rows["g"].Version != 9 || rows["g"].VersionID != "v" || len(rows["g"].UIDList) != 0 {
		t.Fatalf("headers=%+v error=%v", rows, err)
	}
	full, err := d.GetVersionSync(ctx, "members", "g")
	if err != nil || !reflect.DeepEqual(full, want) {
		t.Fatalf("probe changed stored row: %+v %v", full, err)
	}
	if err := d.conn.Model(&model_struct.LocalVersionSync{}).Where("table_name = ?", "members").Update("id_list", "invalid-json").Error; err != nil {
		t.Fatal(err)
	}
	if _, err := d.GetVersionSyncHeaders(ctx, "members", []string{"g"}); err != nil {
		t.Fatal(err)
	}
	if _, err := d.GetVersionSync(ctx, "members", "g"); err == nil {
		t.Fatal("full read should retain malformed payload error")
	}
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := d.GetVersionSyncHeaders(cancelled, "members", []string{"g"}); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if err := d.Close(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := d.GetVersionSyncHeaders(ctx, "members", []string{"g"}); err == nil {
		t.Fatal("closed database must not report successful empty probe")
	}
}

func BenchmarkGroupVersionProbe(b *testing.B) {
	benchmarkGroupVersionProbe(b, 1500)
}

func BenchmarkSmallGroupVersionProbe(b *testing.B) {
	benchmarkGroupVersionProbe(b, 18)
}

func benchmarkGroupVersionProbe(b *testing.B, memberCount int) {
	ctx := context.Background()
	d, err := NewDataBase(ctx, "probe-benchmark", b.TempDir(), 0)
	if err != nil {
		b.Fatal(err)
	}
	b.Cleanup(func() { _ = d.Close(ctx) })
	ids := make([]string, 20)
	members := make([]string, memberCount)
	for i := range members {
		members[i] = fmt.Sprintf("im_%032d", i)
	}
	for i := range ids {
		ids[i] = fmt.Sprintf("g-%d", i)
		if err := d.SetVersionSync(ctx, &model_struct.LocalVersionSync{Table: "members", EntityID: ids[i], VersionID: "v", Version: 7, UIDList: members}); err != nil {
			b.Fatal(err)
		}
	}
	b.Run("full-rows", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			for _, id := range ids {
				if _, err := d.GetVersionSync(ctx, "members", id); err != nil {
					b.Fatal(err)
				}
			}
		}
	})
	b.Run("headers", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			if _, err := d.GetVersionSyncHeaders(ctx, "members", ids); err != nil {
				b.Fatal(err)
			}
		}
	})
}
