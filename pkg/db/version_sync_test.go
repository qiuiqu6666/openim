package db

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
)

func versionSyncTestDB(t *testing.T) (*DataBase, context.Context) {
	t.Helper()
	ctx := context.Background()
	d, err := NewDataBase(ctx, "version-sync-test", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(ctx) })
	return d, ctx
}

func Test_GetVersionSync(t *testing.T) {
	d, ctx := versionSyncTestDB(t)
	want := &model_struct.LocalVersionSync{
		Table: "group-version", EntityID: "group-1", VersionID: "v1",
		Version: 7, UIDList: []string{"member-1", "member-2"},
	}
	if err := d.SetVersionSync(ctx, want); err != nil {
		t.Fatal(err)
	}
	got, err := d.GetVersionSync(ctx, want.Table, want.EntityID)
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("version = %+v, want %+v; error = %v", got, want, err)
	}
	if _, err := d.GetVersionSync(ctx, want.Table, "missing"); !errors.Is(err, errs.ErrRecordNotFound) {
		t.Fatalf("missing version error = %v", err)
	}
}

func Test_SetVersionSync(t *testing.T) {
	d, ctx := versionSyncTestDB(t)
	for _, version := range []uint64{7, 8} {
		want := &model_struct.LocalVersionSync{
			Table: "group-version", EntityID: "group-1",
			Version: version, VersionID: "revision", UIDList: []string{"member"},
		}
		if err := d.SetVersionSync(ctx, want); err != nil {
			t.Fatal(err)
		}
		got, err := d.GetVersionSync(ctx, want.Table, want.EntityID)
		if err != nil || !reflect.DeepEqual(got, want) {
			t.Fatalf("updated version = %+v, want %+v; error = %v", got, want, err)
		}
	}
}

func Test_DeleteVersionSync(t *testing.T) {
	d, ctx := versionSyncTestDB(t)
	for _, id := range []string{"remove", "retain"} {
		if err := d.SetVersionSync(ctx, &model_struct.LocalVersionSync{Table: "group-version", EntityID: id, Version: 1}); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.DeleteVersionSync(ctx, "group-version", "remove"); err != nil {
		t.Fatal(err)
	}
	if _, err := d.GetVersionSync(ctx, "group-version", "remove"); !errors.Is(err, errs.ErrRecordNotFound) {
		t.Fatalf("deleted version error = %v", err)
	}
	if _, err := d.GetVersionSync(ctx, "group-version", "retain"); err != nil {
		t.Fatalf("delete changed another entity: %v", err)
	}
}
