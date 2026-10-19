package group

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	protocol "github.com/openimsdk/protocol/group"
)

func TestMemberBatchesResumeAfterCancelledRequest(t *testing.T) {
	var mu sync.Mutex
	requests := 0
	seen := make(map[string]int)
	var cancel context.CancelFunc
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		var req protocol.BatchGetIncrementalGroupMemberReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Error(err)
			return
		}
		mu.Lock()
		defer mu.Unlock()
		requests++
		if len(req.ReqList) > 20 {
			t.Errorf("oversized batch: %d", len(req.ReqList))
		}
		if requests == 2 {
			cancel()
			return
		}
		for _, item := range req.ReqList {
			seen[item.GroupID]++
		}
		// An entirely empty success confirms every requested group was skipped.
		profileResponse(w, map[string]any{"respList": map[string]any{}})
	})
	base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	first, stop := context.WithCancel(base)
	cancel = stop
	defer stop()
	ids := make([]string, 65)
	for i := range ids {
		ids[i] = fmt.Sprintf("g%03d", i)
	}
	g := NewGroup("self", &groupProfileDB{}, make(chan common.Cmd2Value, 1))
	if err := g.IncrSyncGroupAndMember(first, ids...); err == nil {
		t.Fatal("cancelled request reported success")
	}
	if err := g.IncrSyncGroupAndMember(base, ids...); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	if requests != 5 || len(seen) != len(ids) {
		t.Fatalf("requests=%d completed=%d", requests, len(seen))
	}
	for id, count := range seen {
		if count != 1 {
			t.Errorf("completed group %s fetched %d times", id, count)
		}
	}
}

func TestMemberStorageFailureIsRetriedWithoutRefetchingCompletedGroup(t *testing.T) {
	var mu sync.Mutex
	var requests [][]string
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		var req protocol.BatchGetIncrementalGroupMemberReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Error(err)
			return
		}
		ids := make([]string, 0, len(req.ReqList))
		for _, item := range req.ReqList {
			ids = append(ids, item.GroupID)
		}
		mu.Lock()
		requests = append(requests, ids)
		mu.Unlock()
		profileResponse(w, map[string]any{"respList": map[string]any{"unchanged": map[string]any{}, "g": map[string]any{"versionID": "members", "version": 1, "group": map[string]any{"groupID": "g", "groupName": "New"}}}})
	})
	base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	d := &groupProfileDB{row: &model_struct.LocalGroup{GroupID: "g"}, failMember: true}
	g := NewGroup("self", d, make(chan common.Cmd2Value, 4))
	g.SetGroupListener(func() open_im_sdk_callback.OnGroupListener { return &groupProfileListener{} })
	if err := g.IncrSyncGroupAndMember(base, "g", "unchanged"); err == nil || d.saved != 0 {
		t.Fatal("failed storage checkpointed")
	}
	d.failMember = false
	if err := g.IncrSyncGroupAndMember(base, "g", "unchanged"); err != nil || d.saved != 1 {
		t.Fatalf("retry failed: %v versions=%d", err, d.saved)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(requests) != 2 || len(requests[1]) != 1 || requests[1][0] != "g" {
		t.Fatalf("wrong retry: %v", requests)
	}
}

func TestMemberBatchFailureRetainsSuccessfulSiblings(t *testing.T) {
	var requests [][]string
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		var req protocol.BatchGetIncrementalGroupMemberReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Error(err)
			return
		}
		ids := make([]string, 0, len(req.ReqList))
		for _, item := range req.ReqList {
			ids = append(ids, item.GroupID)
		}
		requests = append(requests, ids)
		if len(requests) == 1 {
			profileResponse(w, map[string]any{"respList": map[string]any{"bad": nil, "unchanged": map[string]any{}}})
		} else {
			profileResponse(w, map[string]any{"respList": map[string]any{}})
		}
	})
	base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	g := NewGroup("self", &groupProfileDB{}, make(chan common.Cmd2Value, 1))
	ids := []string{"unchanged", "bad", "unchanged"}
	if err := g.IncrSyncGroupAndMember(base, ids...); err == nil {
		t.Fatal("nil response acknowledged")
	}
	if err := g.IncrSyncGroupAndMember(base, ids...); err != nil {
		t.Fatal(err)
	}
	if len(requests) != 2 || len(requests[0]) != 2 || len(requests[1]) != 1 || requests[1][0] != "bad" {
		t.Fatalf("retry did not retain sibling: %v", requests)
	}
	// A completed sweep must allow a later refresh to observe new changes.
	if err := g.IncrSyncGroupAndMember(base, ids...); err != nil {
		t.Fatal(err)
	}
	if len(requests[2]) != 2 {
		t.Fatal("completed sweep suppressed new refresh")
	}
}
