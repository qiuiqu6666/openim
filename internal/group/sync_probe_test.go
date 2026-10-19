package group

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync/atomic"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	pbgroup "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
)

type groupProbeDB struct {
	db_interface.DataBase
	fullReads   atomic.Int32
	headerReads atomic.Int32
}

func TestMemberVersionFastPathRequiresExactEmptyDelta(t *testing.T) {
	req := &pbgroup.GetIncrementalGroupMemberReq{VersionID: "v", Version: 7}
	for name, response := range map[string]*pbgroup.GetIncrementalGroupMemberResp{
		"nil":         nil,
		"full":        {VersionID: "v", Version: 7, Full: true},
		"new-version": {VersionID: "v", Version: 8},
		"reset":       {VersionID: "new", Version: 7},
		"profile":     {VersionID: "v", Version: 7, Group: &sdkws.GroupInfo{}},
		"order":       {VersionID: "v", Version: 7, SortVersion: 1},
		"insert":      {VersionID: "v", Version: 7, Insert: []*sdkws.GroupMemberFullInfo{{UserID: "a"}}},
		"update":      {VersionID: "v", Version: 7, Update: []*sdkws.GroupMemberFullInfo{{UserID: "a"}}},
		"delete":      {VersionID: "v", Version: 7, Delete: []string{"a"}},
	} {
		t.Run(name, func(t *testing.T) {
			if unchangedMemberVersion(req, response) {
				t.Fatal("required sync was skipped")
			}
		})
	}
	if unchangedMemberVersion(&pbgroup.GetIncrementalGroupMemberReq{}, &pbgroup.GetIncrementalGroupMemberResp{}) {
		t.Fatal("uninitialized versions cannot prove unchanged state")
	}
}

func (d *groupProbeDB) GetVersionSync(_ context.Context, table, id string) (*model_struct.LocalVersionSync, error) {
	d.fullReads.Add(1)
	return &model_struct.LocalVersionSync{Table: table, EntityID: id, VersionID: "current", Version: 7, UIDList: make([]string, 1500)}, nil
}

func (d *groupProbeDB) GetVersionSyncHeaders(_ context.Context, table string, ids []string) (map[string]*model_struct.LocalVersionSync, error) {
	d.headerReads.Add(1)
	result := make(map[string]*model_struct.LocalVersionSync, len(ids))
	for _, id := range ids {
		result[id] = &model_struct.LocalVersionSync{Table: table, EntityID: id, VersionID: "current", Version: 7}
	}
	return result, nil
}

func TestUnchangedLargeGroupSweepDoesNotLoadMemberIDLists(t *testing.T) {
	var requests atomic.Int32
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		var req pbgroup.BatchGetIncrementalGroupMemberReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Error(err)
			return
		}
		requests.Add(1)
		resp := make(map[string]*pbgroup.GetIncrementalGroupMemberResp)
		for _, item := range req.ReqList {
			resp[item.GroupID] = &pbgroup.GetIncrementalGroupMemberResp{VersionID: item.VersionID, Version: item.Version}
		}
		profileResponse(w, &pbgroup.BatchGetIncrementalGroupMemberResp{RespList: resp})
	})
	d := &groupProbeDB{}
	g := NewGroup("self", d, nil)
	ids := make([]string, 3116)
	for i := range ids {
		ids[i] = fmt.Sprintf("g-%04d", i)
	}
	if err := g.IncrSyncGroupAndMember(ctx, ids...); err != nil {
		t.Fatal(err)
	}
	if d.fullReads.Load() != 0 {
		t.Fatalf("unchanged sweep decoded full member lists %d times", d.fullReads.Load())
	}
	if d.headerReads.Load() != requests.Load() || requests.Load() != 156 {
		t.Fatalf("header reads=%d requests=%d", d.headerReads.Load(), requests.Load())
	}
}

func TestMemberBatchRetriesGroupsOmittedByServerResponseBudget(t *testing.T) {
	var requested []int
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		var req pbgroup.BatchGetIncrementalGroupMemberReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Error(err)
			return
		}
		requested = append(requested, len(req.ReqList))
		first := req.ReqList[0]
		profileResponse(w, &pbgroup.BatchGetIncrementalGroupMemberResp{RespList: map[string]*pbgroup.GetIncrementalGroupMemberResp{
			first.GroupID: {VersionID: first.VersionID, Version: first.Version},
		}})
	})
	g := NewGroup("self", &groupProbeDB{}, nil)
	if err := g.IncrSyncGroupAndMember(ctx, "a", "b", "c"); err != nil {
		t.Fatal(err)
	}
	if len(requested) != 3 || requested[0] != 3 || requested[1] != 2 || requested[2] != 1 {
		t.Fatalf("server omitted unprocessed groups, requests=%v", requested)
	}
}
