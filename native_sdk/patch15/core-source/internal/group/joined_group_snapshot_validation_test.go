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
	protocol "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
)

func TestJoinedGroupRetryRejectsStalePrefixes(t *testing.T) {
	for _, change := range []string{"version", "version-id", "sort", "obligation"} {
		t.Run(change, func(t *testing.T) {
			var mu sync.Mutex
			version := joinedGroupVersion{"v", 1, 1}
			var cancel context.CancelFunc
			failed := false
			var pages []int32
			ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				defer mu.Unlock()
				switch r.URL.Path {
				case "/group/get_incremental_join_groups":
					profileResponse(w, map[string]any{"full": true, "versionID": version.id, "version": version.version, "sortVersion": version.sortVersion})
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
					var groups []*sdkws.GroupInfo
					if req.Pagination.PageNumber == 1 {
						for i := 0; i < 200; i++ {
							groups = append(groups, &sdkws.GroupInfo{GroupID: fmt.Sprint(i), GroupName: version.id})
						}
					}
					profileResponse(w, map[string]any{"groups": groups})
				case "/group/get_full_join_group_ids":
					ids := make([]string, 200)
					for i := range ids {
						ids[i] = fmt.Sprint(i)
					}
					profileResponse(w, map[string]any{"groupIDs": ids})
				default:
					t.Errorf("unexpected endpoint %s", r.URL.Path)
				}
			})
			base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
			first, stop := context.WithCancel(base)
			cancel = stop
			defer stop()
			g, d := newJoinedResumeGroup()
			if _, err := g.IncrSyncJoinGroupAndGetIDs(first); err == nil {
				t.Fatal("expected cancellation")
			}
			mu.Lock()
			switch change {
			case "version":
				version.version++
			case "version-id":
				version.id = "new"
			case "sort":
				version.sortVersion++
			case "obligation":
				base = common.WithMetadataProgress(ctx, &common.MetadataProgress{})
			}
			mu.Unlock()
			if _, err := g.IncrSyncJoinGroupAndGetIDs(base); err != nil {
				t.Fatal(err)
			}
			mu.Lock()
			defer mu.Unlock()
			if !reflect.DeepEqual(pages, []int32{1, 2, 1, 2}) {
				t.Fatalf("stale prefix reused: %v", pages)
			}
			if len(d.rows) != 200 || d.rows["0"].GroupName != version.id {
				t.Fatal("mixed snapshot applied")
			}
		})
	}
}

func TestJoinedGroupSnapshotValidatesBeforeRemovingLocalGroups(t *testing.T) {
	for _, problem := range []string{"version-changed", "missing-id", "duplicate", "nil-row", "id-failure", "verify-failure"} {
		t.Run(problem, func(t *testing.T) {
			var mu sync.Mutex
			bad := true
			versionCalls := 0
			ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				defer mu.Unlock()
				switch r.URL.Path {
				case "/group/get_incremental_join_groups":
					versionCalls++
					version := 1
					if bad && versionCalls > 1 {
						if problem == "version-changed" {
							version++
						}
						if problem == "verify-failure" {
							w.WriteHeader(500)
							return
						}
					}
					profileResponse(w, map[string]any{"full": true, "versionID": "v", "version": version})
				case "/group/get_joined_group_list":
					groups := []*sdkws.GroupInfo{{GroupID: "new"}}
					if bad && problem == "duplicate" {
						groups = append(groups, groups[0])
					}
					if bad && problem == "nil-row" {
						groups = []*sdkws.GroupInfo{nil}
					}
					profileResponse(w, map[string]any{"groups": groups})
				case "/group/get_full_join_group_ids":
					if bad && problem == "id-failure" {
						w.WriteHeader(500)
						return
					}
					ids := []string{"new"}
					if bad && problem == "missing-id" {
						ids = append(ids, "missing")
					}
					profileResponse(w, map[string]any{"groupIDs": ids})
				default:
					t.Errorf("unexpected endpoint %s", r.URL.Path)
				}
			})
			base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
			g, d := newJoinedResumeGroup()
			if _, err := g.IncrSyncJoinGroupAndGetIDs(base); err == nil {
				t.Fatal("unsafe snapshot accepted")
			}
			if d.writes != 0 || d.saved != 0 || d.rows["old"] == nil {
				t.Fatal("failed validation removed local group")
			}
			mu.Lock()
			bad = false
			mu.Unlock()
			if _, err := g.IncrSyncJoinGroupAndGetIDs(base); err != nil {
				t.Fatal(err)
			}
			if len(d.rows) != 1 || d.rows["new"] == nil || d.saved != 1 {
				t.Fatal("validated snapshot was not published")
			}
		})
	}
}

func TestJoinedGroupEmptySnapshotIsAuthoritative(t *testing.T) {
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/group/get_incremental_join_groups":
			profileResponse(w, map[string]any{"full": true, "versionID": "v", "version": 1})
		case "/group/get_joined_group_list":
			profileResponse(w, map[string]any{"groups": []any{}})
		case "/group/get_full_join_group_ids":
			profileResponse(w, map[string]any{"groupIDs": []string{}})
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
		}
	})
	g, d := newJoinedResumeGroup()
	if _, err := g.IncrSyncJoinGroupAndGetIDs(ctx); err != nil {
		t.Fatal(err)
	}
	if len(d.rows) != 0 || d.saved != 1 {
		t.Fatal("confirmed empty snapshot was ignored")
	}
}
