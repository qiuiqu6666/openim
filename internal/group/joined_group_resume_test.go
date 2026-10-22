package group

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"reflect"
	"sync"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/syncer"
	protocol "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
)

type joinedResumeDB struct {
	groupProfileDB
	rows   map[string]*model_struct.LocalGroup
	writes int
}

func (d *joinedResumeDB) GetJoinedGroupListDB(context.Context) ([]*model_struct.LocalGroup, error) {
	var rows []*model_struct.LocalGroup
	for _, row := range d.rows {
		rows = append(rows, row)
	}
	return rows, nil
}

func newJoinedResumeGroup() (*Group, *joinedResumeDB) {
	d := &joinedResumeDB{rows: map[string]*model_struct.LocalGroup{"old": {GroupID: "old"}}}
	g := NewGroup("self", d, make(chan common.Cmd2Value, 4096))
	g.groupSyncer = syncer.New[*model_struct.LocalGroup, protocol.GetJoinedGroupListResp, string](
		func(_ context.Context, row *model_struct.LocalGroup) error {
			d.rows[row.GroupID] = row
			d.writes++
			return nil
		},
		func(_ context.Context, row *model_struct.LocalGroup) error {
			delete(d.rows, row.GroupID)
			d.writes++
			return nil
		},
		func(_ context.Context, row, _ *model_struct.LocalGroup) error {
			d.rows[row.GroupID] = row
			d.writes++
			return nil
		},
		func(row *model_struct.LocalGroup) string { return row.GroupID }, nil, nil,
	)
	return g, d
}

// Exercise the production full-sync path, not only a pagination helper. A
// cancelled page must neither publish a partial directory nor lose its prefix.
func TestJoinedGroupPagesResumeWithoutPublishingPartialDirectory(t *testing.T) {
	var mu sync.Mutex
	var pages []int32
	var cancel context.CancelFunc
	failed := false
	groups := make([]*sdkws.GroupInfo, 401)
	ids := make([]string, len(groups))
	for i := range groups {
		ids[i] = fmt.Sprintf("g%03d", i)
		groups[i] = &sdkws.GroupInfo{GroupID: ids[i]}
	}
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch r.URL.Path {
		case "/group/get_incremental_join_groups":
			profileResponse(w, map[string]any{"full": true, "versionID": "groups", "version": 5})
		case "/group/get_joined_group_list":
			var req protocol.GetJoinedGroupListReq
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Error(err)
				return
			}
			pages = append(pages, req.Pagination.PageNumber)
			if req.Pagination.PageNumber == 2 && !failed {
				failed = true
				cancel()
				return
			}
			start := min(int((req.Pagination.PageNumber-1)*req.Pagination.ShowNumber), len(groups))
			end := min(start+int(req.Pagination.ShowNumber), len(groups))
			profileResponse(w, map[string]any{"groups": groups[start:end]})
		case "/group/get_full_join_group_ids":
			profileResponse(w, map[string]any{"groupIDs": ids})
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
			w.WriteHeader(500)
		}
	})
	base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	first, stop := context.WithCancel(base)
	cancel = stop
	defer stop()
	g, d := newJoinedResumeGroup()
	if _, err := g.IncrSyncJoinGroupAndGetIDs(first); err == nil {
		t.Fatal("cancelled sync succeeded")
	}
	if d.writes != 0 || d.saved != 0 || d.rows["old"] == nil {
		t.Fatal("partial directory published")
	}
	if _, err := g.IncrSyncJoinGroupAndGetIDs(base); err != nil {
		t.Fatal(err)
	}
	if len(d.rows) != 401 || d.rows["old"] != nil || d.saved != 1 {
		t.Fatalf("rows=%d versions=%d", len(d.rows), d.saved)
	}
	mu.Lock()
	defer mu.Unlock()
	if !reflect.DeepEqual(pages, []int32{1, 2, 2, 3}) {
		t.Fatalf("completed prefix fetched again: %v", pages)
	}
}
