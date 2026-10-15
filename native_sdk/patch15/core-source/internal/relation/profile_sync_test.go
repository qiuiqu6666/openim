package relation

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/internal/user"
	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type friendProfileDB struct {
	db_interface.DataBase
	rows     map[string]model_struct.LocalFriend
	writeErr error
	updates  int
}

func (d *friendProfileDB) GetVersionSync(context.Context, string, string) (*model_struct.LocalVersionSync, error) {
	return &model_struct.LocalVersionSync{VersionID: "same", Version: 7}, nil
}
func (d *friendProfileDB) GetAllFriendList(ctx context.Context) ([]*model_struct.LocalFriend, error) {
	ids := make([]string, 0, len(d.rows))
	for id := range d.rows {
		ids = append(ids, id)
	}
	return d.GetFriendInfoList(ctx, ids)
}
func (d *friendProfileDB) GetFriendInfoList(_ context.Context, ids []string) ([]*model_struct.LocalFriend, error) {
	var result []*model_struct.LocalFriend
	for _, id := range ids {
		if row, ok := d.rows[id]; ok {
			copy := row
			result = append(result, &copy)
		}
	}
	return result, nil
}
func (d *friendProfileDB) UpdateFriend(_ context.Context, row *model_struct.LocalFriend) error {
	if d.writeErr != nil {
		return d.writeErr
	}
	d.rows[row.FriendUserID] = *row
	d.updates++
	return nil
}

type friendProfileListener struct {
	open_im_sdk_callback.OnFriendshipListenerSdk
	db      *friendProfileDB
	t       *testing.T
	changed []model_struct.LocalFriend
}

func (l *friendProfileListener) OnFriendInfoChanged(row model_struct.LocalFriend) {
	if l.db.rows[row.FriendUserID] != row {
		l.t.Fatal("notification before persistence")
	}
	l.changed = append(l.changed, row)
}

func friendProfileFixture(t *testing.T, count int) (*Relation, *friendProfileDB, *friendProfileListener, context.Context, *int, *string) {
	t.Helper()
	d := &friendProfileDB{rows: map[string]model_struct.LocalFriend{}}
	for i := 0; i < count; i++ {
		id := fmt.Sprint(i)
		d.rows[id] = model_struct.LocalFriend{OwnerUserID: "self", FriendUserID: id, Nickname: "old", FaceURL: "old-avatar", Remark: "my remark"}
	}
	calls := 0
	mode := "success"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		data := map[string]any{"versionID": "same", "version": 7}
		if req.URL.Path == "/friend/get_designated_friends" {
			calls++
			if mode == "network" {
				http.Error(w, "temporary failure", 503)
				return
			}
			var body struct {
				FriendUserIDs []string `json:"friendUserIDs"`
			}
			_ = json.NewDecoder(req.Body).Decode(&body)
			if len(body.FriendUserIDs) > friendProfileBatchSize {
				t.Error("unbounded profile request")
			}
			rows := []any{}
			for _, id := range body.FriendUserIDs {
				if mode == "partial" {
					break
				}
				face := "new-avatar"
				if mode == "clear" {
					face = ""
				}
				rows = append(rows, map[string]any{"ownerUserID": "self", "remark": "my remark", "friendUser": map[string]any{"userID": id, "nickname": "latest", "faceURL": face}})
			}
			data = map[string]any{"friendsInfo": rows}
		} else if req.URL.Path != "/friend/get_incremental_friends" {
			t.Errorf("unexpected route %s", req.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data})
	}))
	t.Cleanup(server.Close)
	ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "friend-profile-test"), &ccontext.GlobalConfig{UserID: "self", IMConfig: sdk_struct.IMConfig{ApiAddr: server.URL}})
	ch := make(chan common.Cmd2Value, 1000)
	r := NewFriend("self", d, user.NewUser(d, "self", ch), ch)
	l := &friendProfileListener{t: t, db: d}
	r.friendshipListener = l
	return r, d, l, ctx, &calls, &mode
}

func TestFriendProfilesRepairUnchangedRosterInBoundedBatches(t *testing.T) {
	r, d, l, ctx, calls, _ := friendProfileFixture(t, 205)
	r.user.UserCache().Store("0", &model_struct.LocalUser{UserID: "0", Nickname: "stale cache"})
	if err := r.SyncFriendsWithProfilesWithLock(ctx); err != nil {
		t.Fatal(err)
	}
	if *calls != 3 || d.updates != 205 || len(l.changed) != 205 {
		t.Fatalf("calls=%d writes=%d notices=%d", *calls, d.updates, len(l.changed))
	}
	if _, ok := r.user.UserCache().Load("0"); ok {
		t.Fatal("public user cache was not invalidated")
	}
	if d.rows["0"].Nickname != "latest" || d.rows["0"].Remark != "my remark" {
		t.Fatal(d.rows["0"])
	}
	if err := r.SyncFriendsWithProfilesWithLock(ctx); err != nil {
		t.Fatal(err)
	}
	if *calls != 3 {
		t.Fatal("duplicate recovery pass inside cooldown")
	}
	r.friendProfilesSyncedAt = time.Now().Add(-2 * time.Minute)
	if err := r.SyncFriendsWithProfilesWithLock(ctx); err != nil {
		t.Fatal(err)
	}
	if *calls != 6 || len(l.changed) != 205 {
		t.Fatal("unchanged profiles duplicated notices")
	}
}

func TestFriendProfileFailuresRemainRetryableAndKeepOldRows(t *testing.T) {
	for _, failure := range []string{"network", "partial", "storage", "cancel"} {
		t.Run(failure, func(t *testing.T) {
			r, d, l, ctx, _, mode := friendProfileFixture(t, 1)
			*mode = failure
			if failure == "storage" {
				d.writeErr = errors.New("disk unavailable")
			}
			if failure == "cancel" {
				var cancel context.CancelFunc
				ctx, cancel = context.WithCancel(ctx)
				cancel()
			}
			if err := r.SyncFriendsWithProfilesWithLock(ctx); err == nil {
				t.Fatal("failed pass acknowledged")
			}
			if !r.friendProfilesSyncedAt.IsZero() || len(l.changed) != 0 || d.rows["0"].Nickname != "old" {
				t.Fatal("failed pass changed visible identity")
			}
			if failure != "cancel" {
				*mode = "success"
				d.writeErr = nil
				if err := r.SyncFriendsWithProfilesWithLock(ctx); err != nil {
					t.Fatal(err)
				}
				if len(l.changed) != 1 {
					t.Fatal("retry failed")
				}
			}
		})
	}
}

func TestFriendProfileNotificationBypassesRosterVersionAndCooldown(t *testing.T) {
	r, d, l, ctx, calls, mode := friendProfileFixture(t, 1)
	r.friendProfilesSyncedAt = time.Now()
	*mode = "clear"
	content, _ := json.Marshal(map[string]any{"detail": "{\"userID\":\"0\"}"})
	msg := &sdkws.MsgData{ContentType: constant.FriendInfoUpdatedNotification, Content: content}
	if err := r.DoNotification(ctx, msg); err != nil {
		t.Fatal(err)
	}
	if *calls != 1 || len(l.changed) != 1 || d.rows["0"].Nickname != "latest" || d.rows["0"].FaceURL != "" {
		t.Fatal("profile event did not refresh cleared avatar")
	}
	delete(d.rows, "0")
	if err := r.DoNotification(ctx, msg); err != nil {
		t.Fatal(err)
	}
	if *calls != 1 || len(d.rows) != 0 {
		t.Fatal("deleted friend was resurrected")
	}
}
