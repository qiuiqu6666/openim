package database

import (
	"context"
	table "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"go.mongodb.org/mongo-driver/mongo"
	"testing"
	"time"
)

type privacyTx struct{}

func (privacyTx) Transaction(ctx context.Context, fn func(context.Context) error) error {
	return fn(ctx)
}

type privacyStore struct {
	table.MomentStore
	rows            map[string]*table.MomentSettings
	blocked, hidden map[string]map[string]bool
}

func (s *privacyStore) TakeSettings(_ context.Context, id string) (*table.MomentSettings, error) {
	if row := s.rows[id]; row != nil {
		copy := *row
		return &copy, nil
	}
	return nil, mongo.ErrNoDocuments
}
func (s *privacyStore) InsertSettings(_ context.Context, row *table.MomentSettings) error {
	copy := *row
	s.rows[row.UserID] = &copy
	return nil
}
func (s *privacyStore) UpdateSettings(_ context.Context, id string, version int64, fields map[string]any, next int64) (bool, error) {
	row := s.rows[id]
	if row == nil || row.Version != version {
		return false, nil
	}
	for k, v := range fields {
		applySetting(row, k, v)
	}
	row.Version = next
	return true, nil
}
func edge(m map[string]map[string]bool, owner, id string, enabled bool) (bool, error) {
	if m[owner] == nil {
		m[owner] = map[string]bool{}
	}
	old := m[owner][id]
	if enabled {
		m[owner][id] = true
	} else {
		delete(m[owner], id)
	}
	return old != enabled, nil
}
func ids(m map[string]map[string]bool, id string) (out []string, err error) {
	for v := range m[id] {
		out = append(out, v)
	}
	return
}
func (s *privacyStore) PutBlockedViewer(_ context.Context, a, b string) (bool, error) {
	return edge(s.blocked, a, b, true)
}
func (s *privacyStore) DeleteBlockedViewer(_ context.Context, a, b string) (bool, error) {
	return edge(s.blocked, a, b, false)
}
func (s *privacyStore) PutHiddenAuthor(_ context.Context, a, b string) (bool, error) {
	return edge(s.hidden, a, b, true)
}
func (s *privacyStore) DeleteHiddenAuthor(_ context.Context, a, b string) (bool, error) {
	return edge(s.hidden, a, b, false)
}
func (s *privacyStore) ListBlockedViewers(_ context.Context, a string) ([]string, error) {
	return ids(s.blocked, a)
}
func (s *privacyStore) ListHiddenAuthors(_ context.Context, a string) ([]string, error) {
	return ids(s.hidden, a)
}
func newPrivacyDB() *MomentDatabase {
	return &MomentDatabase{tx: privacyTx{}, store: &privacyStore{rows: map[string]*table.MomentSettings{}, blocked: map[string]map[string]bool{}, hidden: map[string]map[string]bool{}}}
}
func TestPrivacySettingsServerTimestamp(t *testing.T) {
	d := newPrivacyDB()
	ctx := context.Background()
	now := time.UnixMilli(1700000000123)
	fields := map[string]any{"visible_range_days": int32(90)}
	row, err := d.PatchSettings(ctx, "me", 0, fields, now)
	if err != nil || row.UpdatedAt != now.UnixMilli() || row.Version != 1 {
		t.Fatalf("row=%+v err=%v", row, err)
	}
	if _, ok := fields["updated_at"]; ok {
		t.Fatal("mutated caller fields")
	}
	row, err = d.PatchSettings(ctx, "me", 1, map[string]any{"visible_range_days": int32(3)}, now.Add(time.Second))
	if err != nil || row.UpdatedAt != now.Add(time.Second).UnixMilli() || row.Version != 2 {
		t.Fatalf("row=%+v err=%v", row, err)
	}
	if _, err = d.PatchSettings(ctx, "me", 1, fields, now); err != ErrMomentVersion {
		t.Fatalf("expected conflict got %v", err)
	}
}
func TestPrivacyListsOwnerIsolationAndIdempotentTimestamp(t *testing.T) {
	for _, hidden := range []bool{false, true} {
		d := newPrivacyDB()
		ctx := context.Background()
		put := d.PutBlockedViewer
		del := d.DeleteBlockedViewer
		if hidden {
			put = d.PutHiddenAuthor
			del = d.DeleteHiddenAuthor
		}
		row, err := del(ctx, "me", "peer")
		if err != nil || row.UpdatedAt != 0 || row.Version != 0 {
			t.Fatal("no-op must not invent timestamp", row, err)
		}
		before := time.Now().UnixMilli()
		row, err = put(ctx, "me", "peer")
		if err != nil || row.UpdatedAt < before || row.Version != 1 {
			t.Fatal(row, err)
		}
		stamp := row.UpdatedAt
		row, err = put(ctx, "me", "peer")
		if err != nil || row.UpdatedAt != stamp || row.Version != 1 {
			t.Fatal("idempotent add changed timestamp", row, err)
		}
		_, b, h, err := d.SettingsSnapshot(ctx, "me")
		if err != nil || len(b)+len(h) != 1 {
			t.Fatal(b, h, err)
		}
		row, b, h, err = d.SettingsSnapshot(ctx, "other")
		if err != nil || len(b)+len(h) != 0 || row.UpdatedAt != 0 {
			t.Fatal("owner leakage", row, b, h, err)
		}
		row, err = del(ctx, "me", "peer")
		if err != nil || row.Version != 2 || row.UpdatedAt < stamp {
			t.Fatal(row, err)
		}
		_, b, h, err = d.SettingsSnapshot(ctx, "me")
		if err != nil || len(b)+len(h) != 0 {
			t.Fatal(b, h, err)
		}
	}
}
