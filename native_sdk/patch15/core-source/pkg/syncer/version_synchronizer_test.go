package syncer

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type profileVersionDB struct{ saved int }

func (d *profileVersionDB) GetVersionSync(context.Context, string, string) (*model_struct.LocalVersionSync, error) {
	return &model_struct.LocalVersionSync{}, nil
}
func (d *profileVersionDB) SetVersionSync(context.Context, *model_struct.LocalVersionSync) error {
	d.saved++
	return nil
}
func (d *profileVersionDB) DeleteVersionSync(context.Context, string, string) error { return nil }

func TestFullMemberSyncAppliesProfileBeforeVersion(t *testing.T) {
	for _, fail := range []bool{false, true} {
		db := &profileVersionDB{}
		applied := 0
		s := VersionSynchronizer[string, *int]{
			Ctx: context.Background(), DB: db,
			ServerVersion: func() *int { v := 1; return &v },
			Delete:        func(*int) []string { return nil }, Update: func(*int) []string { return nil }, Insert: func(*int) []string { return nil },
			Full: func(*int) bool { return true }, FullSyncer: func(context.Context) error { return nil },
			FullID:    func(context.Context) ([]string, error) { return []string{"member"}, nil },
			ExtraData: func(v *int) any { return v },
			ExtraDataProcessor: func(context.Context, any) error {
				applied++
				if db.saved != 0 {
					t.Fatal("version committed before profile")
				}
				if fail {
					return errors.New("profile write failed")
				}
				return nil
			},
			Version: func(*int) (string, uint64) { return "members", 9 },
		}
		err := s.IncrementalSync()
		if applied != 1 || (err != nil) != fail {
			t.Fatalf("profile was lost: applied=%d err=%v", applied, err)
		}
		if (db.saved == 0) != fail {
			t.Fatalf("failed profile must not commit version: %d", db.saved)
		}
	}
}

func TestProfileOnlySyncDoesNotLoadMembers(t *testing.T) {
	for _, online := range []bool{false, true} {
		db := &profileVersionDB{}
		applied, sorted := 0, 0
		s := VersionSynchronizer[string, *int]{
			Ctx: context.Background(), DB: db,
			ServerVersion: func() *int { v := 1; return &v },
			Delete:        func(*int) []string { return nil }, Update: func(*int) []string { return nil }, Insert: func(*int) []string { return nil },
			Full: func(*int) bool { return false }, Version: func(*int) (string, uint64) { return "", 1 },
			Local:     func() ([]string, error) { t.Fatal("profile change loaded the member directory"); return nil, nil },
			ExtraData: func(v *int) any { return v }, ExtraDataProcessor: func(context.Context, any) error { applied++; return nil },
			IDOrderChanged: func(*int) bool { return true }, FullID: func(context.Context) ([]string, error) { sorted++; return []string{"member"}, nil },
		}
		var err error
		if online {
			err = s.CheckVersionSync()
		} else {
			err = s.IncrementalSync()
		}
		if err != nil || applied != 1 || db.saved != 1 || sorted != 1 {
			t.Fatalf("profile/version/order was lost: %v %d/%d/%d", err, applied, db.saved, sorted)
		}
	}
}
