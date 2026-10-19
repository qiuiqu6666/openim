package group

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

type groupProfileDB struct {
	db_interface.DataBase
	row        *model_struct.LocalGroup
	saved      int
	failMember bool
}

func (d *groupProfileDB) GetVersionSync(context.Context, string, string) (*model_struct.LocalVersionSync, error) {
	return &model_struct.LocalVersionSync{}, nil
}
func (d *groupProfileDB) SetVersionSync(context.Context, *model_struct.LocalVersionSync) error {
	d.saved++
	return nil
}
func (d *groupProfileDB) GetJoinedGroupListDB(context.Context) ([]*model_struct.LocalGroup, error) {
	return []*model_struct.LocalGroup{d.row}, nil
}
func (d *groupProfileDB) GetGroups(context.Context, []string) ([]*model_struct.LocalGroup, error) {
	if d.failMember {
		return nil, errors.New("group storage failed")
	}
	return []*model_struct.LocalGroup{d.row}, nil
}
func (d *groupProfileDB) UpdateGroup(_ context.Context, row *model_struct.LocalGroup) error {
	d.row = row
	return nil
}
func (d *groupProfileDB) GetGroupMemberListByGroupID(context.Context, string) ([]*model_struct.LocalGroupMember, error) {
	if d.failMember {
		return nil, errors.New("member storage failed")
	}
	return nil, nil
}

type groupProfileListener struct {
	open_im_sdk_callback.OnGroupListener
	changed int
}

func (l *groupProfileListener) OnGroupInfoChanged(string) { l.changed++ }

func groupProfileServer(t *testing.T, handler http.HandlerFunc) context.Context {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	ctx := context.WithValue(context.Background(), "operationID", "profile-regression")
	return ccontext.WithInfo(ctx, &ccontext.GlobalConfig{UserID: "self", IMConfig: sdk_struct.IMConfig{ApiAddr: server.URL}})
}
func profileResponse(w http.ResponseWriter, data any) {
	_ = json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data})
}

func TestFullJoinedGroupRefreshNotifiesProfileAndConversation(t *testing.T) {
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/group/get_incremental_join_groups":
			profileResponse(w, map[string]any{"full": true, "versionID": "groups", "version": 5})
		case "/group/get_joined_group_list":
			profileResponse(w, map[string]any{"groups": []any{map[string]any{"groupID": "g", "groupName": "Offline name", "faceURL": "new-avatar"}}})
		case "/group/get_full_join_group_ids":
			profileResponse(w, map[string]any{"groupIDs": []string{"g"}})
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
			w.WriteHeader(500)
		}
	})
	d := &groupProfileDB{row: &model_struct.LocalGroup{GroupID: "g", GroupName: "Old", FaceURL: "old-avatar"}}
	ch := make(chan common.Cmd2Value, 4)
	g := NewGroup("self", d, ch)
	l := &groupProfileListener{}
	g.SetGroupListener(func() open_im_sdk_callback.OnGroupListener { return l })
	if _, err := g.IncrSyncJoinGroupAndGetIDs(ctx); err != nil {
		t.Fatal(err)
	}
	if d.row.GroupName != "Offline name" || d.row.FaceURL != "new-avatar" || l.changed != 1 || len(ch) != 1 || d.saved != 1 {
		t.Fatalf("lost profile notification: row=%+v events=%d commands=%d versions=%d", d.row, l.changed, len(ch), d.saved)
	}
	if cached, ok := g.groupInfoCache.Load("g"); !ok || cached.GroupName != "Offline name" {
		t.Fatal("cache was not refreshed")
	}
}

func TestGroupSyncFailurePropagatesAndCanRetry(t *testing.T) {
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		profileResponse(w, map[string]any{"respList": map[string]any{"g": map[string]any{"versionID": "members", "version": 1, "group": map[string]any{"groupID": "g", "groupName": "New"}}}})
	})
	d := &groupProfileDB{row: &model_struct.LocalGroup{GroupID: "g"}, failMember: true}
	g := NewGroup("self", d, make(chan common.Cmd2Value, 4))
	g.SetGroupListener(func() open_im_sdk_callback.OnGroupListener { return &groupProfileListener{} })
	if err := g.IncrSyncGroupAndMember(ctx, "g"); err == nil || d.saved != 0 {
		t.Fatal("member error was swallowed")
	}
	d.failMember = false
	if err := g.IncrSyncGroupAndMember(ctx, "g"); err != nil || d.saved != 1 {
		t.Fatalf("retry failed: %v", err)
	}
}
