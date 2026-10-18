package group

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
)

type memberRecoveryDB struct {
	groupProfileDB
	members  map[string]*model_struct.LocalGroupMember
	failUser string
}

func (d *memberRecoveryDB) GetGroupMemberListByGroupID(context.Context, string) ([]*model_struct.LocalGroupMember, error) {
	rows := make([]*model_struct.LocalGroupMember, 0, len(d.members))
	for _, row := range d.members {
		rows = append(rows, row)
	}
	return rows, nil
}
func (d *memberRecoveryDB) InsertGroupMember(_ context.Context, row *model_struct.LocalGroupMember) error {
	if row.UserID == d.failUser {
		return errors.New("injected member write failure")
	}
	d.members[row.UserID] = row
	return nil
}
func (d *memberRecoveryDB) UpdateGroupMember(ctx context.Context, row *model_struct.LocalGroupMember) error {
	return d.InsertGroupMember(ctx, row)
}
func (d *memberRecoveryDB) DeleteGroupMember(_ context.Context, _, user string) error {
	delete(d.members, user)
	return nil
}

type memberRecoveryListener struct {
	groupProfileListener
	added, changed, deleted int
}

func (l *memberRecoveryListener) OnGroupMemberAdded(string)       { l.added++ }
func (l *memberRecoveryListener) OnGroupMemberInfoChanged(string) { l.changed++ }
func (l *memberRecoveryListener) OnGroupMemberDeleted(string)     { l.deleted++ }
func recoveryMember(user, name string) *sdkws.GroupMemberFullInfo {
	return &sdkws.GroupMemberFullInfo{GroupID: "g", UserID: user, Nickname: name}
}
func newMemberRecoveryGroup(t *testing.T) (*Group, *memberRecoveryDB, *memberRecoveryListener) {
	t.Helper()
	d := &memberRecoveryDB{groupProfileDB: groupProfileDB{row: &model_struct.LocalGroup{GroupID: "g", GroupName: "Old group", MemberCount: 3}}, members: map[string]*model_struct.LocalGroupMember{
		"rename": {GroupID: "g", UserID: "rename", Nickname: "Old nickname"},
		"remove": {GroupID: "g", UserID: "remove", Nickname: "Removed"},
		"same":   {GroupID: "g", UserID: "same", Nickname: "Unchanged"},
	}}
	g := NewGroup("self", d, make(chan common.Cmd2Value, 4096))
	l := &memberRecoveryListener{}
	g.SetGroupListener(func() open_im_sdk_callback.OnGroupListener { return l })
	for _, row := range d.members {
		g.groupMemberCache.Store(g.buildGroupMemberKey("g", row.UserID), row)
	}
	return g, d, l
}
func memberRecoveryServer(t *testing.T, members []*sdkws.GroupMemberFullInfo, failPage *bool) context.Context {
	return groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/group/get_group_member_list":
			var req group.GetGroupMemberListReq
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Error(err)
				w.WriteHeader(500)
				return
			}
			if failPage != nil && *failPage && req.Pagination.PageNumber == 2 {
				w.WriteHeader(500)
				return
			}
			start := int((req.Pagination.PageNumber - 1) * req.Pagination.ShowNumber)
			end := min(start+int(req.Pagination.ShowNumber), len(members))
			start = min(start, len(members))
			profileResponse(w, map[string]any{"members": members[start:end], "total": len(members)})
		case "/group/get_full_group_member_user_ids":
			ids := make([]string, 0, len(members))
			for _, m := range members {
				ids = append(ids, m.UserID)
			}
			profileResponse(w, map[string]any{"userIDs": ids})
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
			w.WriteHeader(500)
		}
	})
}
func TestMemberRecoveryFullAndIncrementalNotifyProfileCountAndMembers(t *testing.T) {
	for _, full := range []bool{false, true} {
		t.Run(fmt.Sprint(full), func(t *testing.T) {
			members := []*sdkws.GroupMemberFullInfo{recoveryMember("rename", "New nickname"), recoveryMember("same", "Unchanged"), recoveryMember("add", "Added"), recoveryMember("add2", "Added2")}
			ctx := memberRecoveryServer(t, members, nil)
			g, d, l := newMemberRecoveryGroup(t)
			response := &group.GetIncrementalGroupMemberResp{Full: full, VersionID: "v", Version: 2, Group: &sdkws.GroupInfo{GroupID: "g", GroupName: "New group", MemberCount: 4}}
			if !full {
				response.Update = members[:1]
				response.Insert = members[2:]
				response.Delete = []string{"remove"}
			}
			if err := g.syncGroupAndMember(ctx, "g", response); err != nil {
				t.Fatal(err)
			}
			if len(d.members) != 4 || d.members["rename"].Nickname != "New nickname" || d.members["remove"] != nil {
				t.Fatalf("bad members: %+v", d.members)
			}
			if d.row.GroupName != "New group" || d.row.MemberCount != 4 || l.groupProfileListener.changed != 1 || l.changed != 1 || l.added != 2 || l.deleted != 1 || d.saved != 1 {
				t.Fatalf("row=%+v listener=%+v versions=%d", d.row, l, d.saved)
			}
			for _, id := range []string{"rename", "remove"} {
				if _, ok := g.groupMemberCache.Load(g.buildGroupMemberKey("g", id)); ok {
					t.Fatalf("stale cache %s", id)
				}
			}
			if err := g.syncGroupAndMember(ctx, "g", response); err != nil {
				t.Fatal(err)
			}
			if l.changed != 1 || l.added != 2 || l.deleted != 1 {
				t.Fatal("replayed unchanged members generated duplicate events")
			}
		})
	}
}
func TestMemberRecoveryFullFetchFailurePreservesDirectory(t *testing.T) {
	members := make([]*sdkws.GroupMemberFullInfo, 101)
	for i := range members {
		members[i] = recoveryMember(fmt.Sprint(i), "Name")
	}
	fail := true
	ctx := memberRecoveryServer(t, members, &fail)
	g, d, l := newMemberRecoveryGroup(t)
	if err := g.syncFullGroupMembers(ctx, "g"); err == nil {
		t.Fatal("expected page failure")
	}
	if len(d.members) != 3 || l.added+l.changed+l.deleted != 0 {
		t.Fatal("partial page changed live directory")
	}
	fail = false
	if err := g.syncFullGroupMembers(ctx, "g"); err != nil {
		t.Fatal(err)
	}
	if len(d.members) != 101 || l.added != 101 || l.deleted != 3 {
		t.Fatalf("retry lost changes: members=%d listener=%+v", len(d.members), l)
	}
}
func TestMemberRecoveryFullIsNotTruncatedAndRejectsInvalidRows(t *testing.T) {
	t.Run("more-than-1000", func(t *testing.T) {
		members := make([]*sdkws.GroupMemberFullInfo, 1005)
		for i := range members {
			members[i] = recoveryMember(fmt.Sprint(i), "Name")
		}
		ctx := memberRecoveryServer(t, members, nil)
		g, d, l := newMemberRecoveryGroup(t)
		if err := g.syncFullGroupMembers(ctx, "g"); err != nil {
			t.Fatal(err)
		}
		if len(d.members) != 1005 || l.added != 1005 || l.deleted != 3 {
			t.Fatalf("truncated directory: %d", len(d.members))
		}
	})
	for _, invalid := range []string{"foreign", "duplicate"} {
		t.Run(invalid, func(t *testing.T) {
			members := []*sdkws.GroupMemberFullInfo{recoveryMember("u", "Name"), recoveryMember("u", "Name")}
			if invalid == "foreign" {
				members[1].GroupID = "other"
			}
			ctx := memberRecoveryServer(t, members, nil)
			g, d, l := newMemberRecoveryGroup(t)
			if err := g.syncFullGroupMembers(ctx, "g"); err == nil {
				t.Fatal("accepted invalid snapshot")
			}
			if len(d.members) != 3 || l.added+l.changed+l.deleted != 0 {
				t.Fatal("invalid snapshot changed directory")
			}
		})
	}
}
func TestMemberRecoveryWriteFailureKeepsVersionRetryable(t *testing.T) {
	members := []*sdkws.GroupMemberFullInfo{recoveryMember("rename", "New nickname"), recoveryMember("add", "Added")}
	ctx := memberRecoveryServer(t, members, nil)
	g, d, l := newMemberRecoveryGroup(t)
	d.failUser = "add"
	response := &group.GetIncrementalGroupMemberResp{Full: true, VersionID: "v", Version: 2, Group: &sdkws.GroupInfo{GroupID: "g", GroupName: "New group", MemberCount: 2}}
	if err := g.syncGroupAndMember(ctx, "g", response); err == nil {
		t.Fatal("expected storage failure")
	}
	if d.saved != 0 || d.row.GroupName != "Old group" {
		t.Fatal("committed version/profile before member write succeeded")
	}
	d.failUser = ""
	if err := g.syncGroupAndMember(ctx, "g", response); err != nil {
		t.Fatal(err)
	}
	if len(d.members) != 2 || d.saved != 1 || l.changed != 1 || l.added != 1 || l.deleted != 2 || d.row.MemberCount != 2 {
		t.Fatalf("retry incomplete: %+v members=%d", l, len(d.members))
	}
}
