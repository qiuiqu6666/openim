//go:build cgo && !js

package group

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"runtime"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	protocol "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
)

// Exercises real batched SDK HTTP, not just per-profile application. The fixed
// 10ms response delay is synthetic and is reported separately from production RTT.
func BenchmarkGroupProfileNetworkCatchup(b *testing.B) {
	const size = 5000
	var requests atomic.Int64
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request protocol.BatchGetIncrementalGroupMemberReq
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			w.WriteHeader(400)
			return
		}
		requests.Add(1)
		time.Sleep(10 * time.Millisecond)
		responses := make(map[string]*protocol.GetIncrementalGroupMemberResp, len(request.ReqList))
		for _, item := range request.ReqList {
			responses[item.GroupID] = &protocol.GetIncrementalGroupMemberResp{VersionID: "stress", Version: 1, Group: &sdkws.GroupInfo{GroupID: item.GroupID, GroupName: "After network", FaceURL: "new", GroupType: 2}}
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": &protocol.BatchGetIncrementalGroupMemberResp{RespList: responses}})
	}))
	defer server.Close()
	ctx := context.WithValue(context.Background(), "operationID", "group-profile-stress")
	ctx = ccontext.WithInfo(ctx, &ccontext.GlobalConfig{UserID: "network-stress", IMConfig: sdk_struct.IMConfig{ApiAddr: server.URL}})
	database, err := db.NewDataBase(ctx, "network-stress", b.TempDir(), 0)
	if err != nil {
		b.Fatal(err)
	}
	defer database.Close(ctx)
	ids := make([]string, size)
	for start := 0; start < size; start += 100 {
		rows := make([]*model_struct.LocalGroup, 100)
		for i := range rows {
			ids[start+i] = fmt.Sprintf("g%06d", start+i)
			rows[i] = &model_struct.LocalGroup{GroupID: ids[start+i], GroupName: "Before", FaceURL: "old", GroupType: 2}
		}
		if err := database.BatchInsertGroup(ctx, rows); err != nil {
			b.Fatal(err)
		}
	}
	ch := make(chan common.Cmd2Value, size+1)
	g := NewGroup("network-stress", database, ch)
	listener := &stressGroupListener{}
	g.SetGroupListener(func() open_im_sdk_callback.OnGroupListener { return listener })
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	b.ResetTimer()
	if err := g.IncrSyncGroupAndMember(ctx, ids...); err != nil {
		b.Fatal(err)
	}
	b.StopTimer()
	runtime.ReadMemStats(&after)
	actual, err := database.GetJoinedGroupListDB(ctx)
	if err != nil {
		b.Fatal(err)
	}
	for _, row := range actual {
		if row.GroupName != "After network" || row.FaceURL != "new" {
			b.Fatalf("missed %s", row.GroupID)
		}
	}
	if len(actual) != size || listener.count.Load() != size || len(ch) != size {
		b.Fatal("incomplete network catchup")
	}
	b.ReportMetric(float64(requests.Load()), "HTTP-requests")
	b.ReportMetric(float64(after.TotalAlloc-before.TotalAlloc)/1048576, "alloc-MiB")
	b.ReportMetric(float64(after.HeapAlloc)/1048576, "end-heap-MiB")
}
