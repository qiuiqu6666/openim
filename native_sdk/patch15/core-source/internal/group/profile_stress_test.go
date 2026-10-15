//go:build cgo && !js

package group

import (
	"context"
	"fmt"
	"runtime"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	protocol "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
)

type stressGroupListener struct {
	open_im_sdk_callback.OnGroupListener
	count atomic.Int64
}

func (l *stressGroupListener) OnGroupInfoChanged(string) { l.count.Add(1) }

// The same benchmark is run on the unmodified release and the optimized source.
// It includes real SQLite writes, cache updates, serialized profile callbacks,
// conversation commands and version commits. It excludes network latency.
func BenchmarkGroupProfileCatchup(b *testing.B) {
	for _, size := range []int{1000, 5000} {
		b.Run(fmt.Sprint(size), func(b *testing.B) {
			ctx := ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{UserID: "stress"})
			database, err := db.NewDataBase(ctx, "stress", b.TempDir(), 0)
			if err != nil {
				b.Fatal(err)
			}
			defer database.Close(ctx)
			rows := make([]*model_struct.LocalGroup, size)
			for i := range rows {
				rows[i] = &model_struct.LocalGroup{GroupID: fmt.Sprintf("g%06d", i), GroupName: "Before", FaceURL: "old", GroupType: 2}
			}
			for start := 0; start < len(rows); start += 100 {
				end := start + 100
				if end > len(rows) {
					end = len(rows)
				}
				if err := database.BatchInsertGroup(ctx, rows[start:end]); err != nil {
					b.Fatal(err)
				}
			}
			ch := make(chan common.Cmd2Value, size*(b.N+1))
			g := NewGroup("stress", database, ch)
			listener := &stressGroupListener{}
			g.SetGroupListener(func() open_im_sdk_callback.OnGroupListener { return listener })
			runtime.GC()
			var before, after runtime.MemStats
			runtime.ReadMemStats(&before)
			var peak atomic.Uint64
			peak.Store(before.HeapAlloc)
			done, stopped := make(chan struct{}), make(chan struct{})
			go func() {
				defer close(stopped)
				ticker := time.NewTicker(10 * time.Millisecond)
				defer ticker.Stop()
				for {
					select {
					case <-done:
						return
					case <-ticker.C:
						var m runtime.MemStats
						runtime.ReadMemStats(&m)
						for old := peak.Load(); m.HeapAlloc > old; old = peak.Load() {
							if peak.CompareAndSwap(old, m.HeapAlloc) {
								break
							}
						}
					}
				}
			}()
			b.ResetTimer()
			for turn := 0; turn < b.N; turn++ {
				for i, row := range rows {
					face := "new"
					if i%11 == 0 {
						face = ""
					}
					info := &sdkws.GroupInfo{GroupID: row.GroupID, GroupName: fmt.Sprintf("After %d", turn), FaceURL: face, GroupType: 2}
					if err := g.syncGroupAndMember(ctx, row.GroupID, &protocol.GetIncrementalGroupMemberResp{Group: info, VersionID: "stress", Version: uint64(turn + 1)}); err != nil {
						b.Fatal(err)
					}
				}
			}
			b.StopTimer()
			close(done)
			<-stopped
			runtime.ReadMemStats(&after)
			b.ReportMetric(float64(after.TotalAlloc-before.TotalAlloc)/1024/1024/float64(b.N), "alloc-MiB/op")
			b.ReportMetric(float64(peak.Load())/1024/1024, "peak-heap-MiB")
			actual, err := database.GetJoinedGroupListDB(ctx)
			if err != nil {
				b.Fatal(err)
			}
			for i, row := range actual {
				_ = i
				if row.GroupName != fmt.Sprintf("After %d", b.N-1) {
					b.Fatalf("missed group %s", row.GroupID)
				}
			}
			if listener.count.Load() != int64(size*b.N) || len(ch) != size*b.N {
				b.Fatalf("missing updates: groups=%d commands=%d", listener.count.Load(), len(ch))
			}
			b.ReportMetric(float64(listener.count.Load())/float64(b.N), "verified-groups/op")
		})
	}
}
