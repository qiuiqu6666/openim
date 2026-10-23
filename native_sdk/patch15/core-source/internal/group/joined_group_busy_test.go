package group

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	protocol "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
)

type joinedBusyWorker struct {
	g     *Group
	queue chan common.Cmd2Value
	live  atomic.Int32
}

func (w *joinedBusyWorker) GetCh() chan common.Cmd2Value                 { return w.queue }
func (w *joinedBusyWorker) InterruptibleCommand(c common.Cmd2Value) bool { return c.Cmd == "groups" }
func (w *joinedBusyWorker) Work(c common.Cmd2Value) {
	if c.Cmd != "groups" {
		w.live.Add(1)
		return
	}
	_, err := w.g.IncrSyncJoinGroupAndGetIDs(c.Ctx)
	c.Receipt <- err
}

func TestJoinedGroupSnapshotFinishesWithContinuousLiveTraffic(t *testing.T) {
	var mu sync.Mutex
	pages := make(map[int32]int)
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/group/get_incremental_join_groups":
			profileResponse(w, map[string]any{"full": true, "versionID": "v", "version": 1})
		case "/group/get_joined_group_list":
			var req protocol.GetJoinedGroupListReq
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Error(err)
				return
			}
			mu.Lock()
			pages[req.Pagination.PageNumber]++
			mu.Unlock()
			select {
			case <-r.Context().Done():
				return
			case <-time.After(220 * time.Millisecond):
			}
			var groups []*sdkws.GroupInfo
			start := int((req.Pagination.PageNumber - 1) * req.Pagination.ShowNumber)
			for i := start; i < min(start+int(req.Pagination.ShowNumber), 1201); i++ {
				groups = append(groups, &sdkws.GroupInfo{GroupID: fmt.Sprint(i)})
			}
			profileResponse(w, map[string]any{"groups": groups})
		case "/group/get_full_join_group_ids":
			ids := make([]string, 1201)
			for i := range ids {
				ids[i] = fmt.Sprint(i)
			}
			profileResponse(w, map[string]any{"groupIDs": ids})
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
		}
	})
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	g, d := newJoinedResumeGroup()
	worker := &joinedBusyWorker{g: g, queue: make(chan common.Cmd2Value, 128)}
	done, producerDone := make(chan struct{}), make(chan struct{})
	go func() { defer close(done); common.DoListener(ctx, worker) }()
	go func() {
		defer close(producerDone)
		ticker := time.NewTicker(5 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				select {
				case worker.queue <- common.Cmd2Value{Ctx: ctx, Cmd: "live"}:
				case <-ctx.Done():
					return
				}
			}
		}
	}()
	defer func() { cancel(); <-producerDone; <-done }()
	base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	attempts := 0
	for {
		attempts++
		receipt := make(chan error, 1)
		select {
		case worker.queue <- common.Cmd2Value{Ctx: common.WithMetadataTurn(base), Cmd: "groups", Receipt: receipt}:
		case <-ctx.Done():
			t.Fatal("sync starved before dispatch")
		}
		select {
		case err := <-receipt:
			if err == nil {
				if attempts < 2 || len(d.rows) != 1201 || d.saved != 1 || worker.live.Load() == 0 {
					t.Fatalf("attempts=%d rows=%d versions=%d live=%d", attempts, len(d.rows), d.saved, worker.live.Load())
				}
				mu.Lock()
				count := pages[1]
				mu.Unlock()
				if count != 1 {
					t.Fatalf("first page fetched %d times", count)
				}
				return
			}
		case <-ctx.Done():
			t.Fatal("sync starved under live traffic")
		}
	}
}
