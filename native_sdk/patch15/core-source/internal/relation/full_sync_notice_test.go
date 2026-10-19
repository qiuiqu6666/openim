package relation

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type rosterNoticeRecorder struct {
	open_im_sdk_callback.OnFriendshipListenerSdk
	check   func()
	events  []string
	visible map[string]model_struct.LocalFriend
}

func (r *rosterNoticeRecorder) OnFriendAdded(f model_struct.LocalFriend) {
	r.check()
	r.events = append(r.events, "add:"+f.FriendUserID)
	r.visible[f.FriendUserID] = f
}
func (r *rosterNoticeRecorder) OnFriendInfoChanged(f model_struct.LocalFriend) {
	r.check()
	r.events = append(r.events, "change:"+f.FriendUserID)
	r.visible[f.FriendUserID] = f
}
func (r *rosterNoticeRecorder) OnFriendDeleted(f model_struct.LocalFriend) {
	r.check()
	r.events = append(r.events, "delete:"+f.FriendUserID)
	delete(r.visible, f.FriendUserID)
}

func TestFullFriendSyncPublishesCommittedRosterAfterMessageReadiness(t *testing.T) {
	friend := func(id, remark string) *model_struct.LocalFriend {
		return &model_struct.LocalFriend{OwnerUserID: "owner", FriendUserID: id, Nickname: id, Remark: remark}
	}
	for _, tc := range []struct {
		name          string
		before, after []*model_struct.LocalFriend
		want          []string
	}{
		{"first login", nil, []*model_struct.LocalFriend{friend("a", ""), friend("b", "remark")}, []string{"add:a", "add:b"}},
		{"changed roster", []*model_struct.LocalFriend{friend("a", "old"), friend("b", ""), friend("c", "")}, []*model_struct.LocalFriend{friend("a", "new"), friend("c", ""), friend("d", "")}, []string{"change:a", "add:d", "delete:b"}},
		{"empty roster", []*model_struct.LocalFriend{friend("a", "")}, nil, []string{"delete:a"}},
		{"unchanged roster", []*model_struct.LocalFriend{friend("a", "")}, []*model_struct.LocalFriend{friend("a", "")}, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stored, committed := tc.before, false
			r := &rosterNoticeRecorder{visible: map[string]model_struct.LocalFriend{}, check: func() {
				if !committed {
					t.Fatal("notice preceded storage commit")
				}
			}}
			for _, f := range tc.before {
				r.visible[f.FriendUserID] = *f
			}
			load := func(context.Context) ([]*model_struct.LocalFriend, error) { return stored, nil }
			run := func(context.Context) error { stored = tc.after; committed = true; return nil }
			// The UI already consumed message sync finish and read the old list.
			if err := syncFullFriendsWithNotice(context.Background(), load, run, r); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(r.events, tc.want) {
				t.Fatalf("events=%v want=%v", r.events, tc.want)
			}
			want := map[string]model_struct.LocalFriend{}
			for _, f := range tc.after {
				want[f.FriendUserID] = *f
			}
			if !reflect.DeepEqual(r.visible, want) {
				t.Fatalf("directory did not converge: %v", r.visible)
			}
			r.events = nil
			if err := syncFullFriendsWithNotice(context.Background(), load, run, r); err != nil {
				t.Fatal(err)
			}
			if len(r.events) != 0 {
				t.Fatalf("unchanged retry duplicated notices: %v", r.events)
			}
		})
	}
}

func TestFullFriendSyncDoesNotPublishFailedOrCancelledSnapshots(t *testing.T) {
	for _, stage := range []string{"before read", "sync", "after read", "cancel"} {
		t.Run(stage, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			failure := errors.New(stage)
			reads := 0
			load := func(context.Context) ([]*model_struct.LocalFriend, error) {
				reads++
				if (stage == "before read" && reads == 1) || (stage == "after read" && reads == 2) {
					return nil, failure
				}
				if reads == 1 {
					return nil, nil
				}
				return []*model_struct.LocalFriend{{FriendUserID: "a"}}, nil
			}
			run := func(context.Context) error {
				if stage == "sync" {
					return failure
				}
				if stage == "cancel" {
					cancel()
				}
				return nil
			}
			r := &rosterNoticeRecorder{check: func() { t.Fatal("failed snapshot published") }}
			if err := syncFullFriendsWithNotice(ctx, load, run, r); err == nil {
				t.Fatal("failure was swallowed")
			}
		})
	}
}
