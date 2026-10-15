//go:build cgo && !js

package conversation_msg

import (
	"context"
	"encoding/json"
	"fmt"
	"runtime"
	"strings"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type stressConversationListener struct {
	open_im_sdk_callback.OnConversationListener
	count, largest, bytes int
}

func (l *stressConversationListener) OnConversationChanged(raw string) {
	var rows []*model_struct.LocalConversation
	if err := json.Unmarshal([]byte(raw), &rows); err != nil {
		panic(err)
	}
	l.count += len(rows)
	if len(rows) > l.largest {
		l.largest = len(rows)
	}
	l.bytes += len(raw)
}

func BenchmarkConversationProfileCatchup(b *testing.B) {
	for _, size := range []int{1000, 5000} {
		for _, changed := range []bool{false, true} {
			b.Run(fmt.Sprintf("groups%d-conversations%d-changed%v", size, size*4, changed), func(b *testing.B) {
				ctx := ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{UserID: "stress"})
				database, err := db.NewDataBase(ctx, "stress", b.TempDir(), 0)
				if err != nil {
					b.Fatal(err)
				}
				defer database.Close(ctx)
				groups := make([]*model_struct.LocalGroup, size)
				rows := make([]*model_struct.LocalConversation, size*4)
				for i := range groups {
					groups[i] = &model_struct.LocalGroup{GroupID: fmt.Sprintf("g%06d", i), GroupName: "After", FaceURL: "new", GroupType: 2}
				}
				payload := strings.Repeat("x", 2048)
				for i := range rows {
					rows[i] = &model_struct.LocalConversation{ConversationID: fmt.Sprintf("c%06d", i), ConversationType: constant.SingleChatType, LatestMsgSendTime: int64(i + 1), LatestMsg: payload, ShowName: "Peer", DraftText: "draft", UnreadCount: 7}
					if i < size {
						rows[i].GroupID = groups[i].GroupID
						rows[i].ConversationType = constant.ReadGroupChatType
						rows[i].ShowName = "After"
						rows[i].FaceURL = "new"
						if changed {
							rows[i].ShowName = "Before"
							rows[i].FaceURL = "old"
						}
					}
				}
				for start := 0; start < len(groups); start += 100 {
					end := start + 100
					if end > len(groups) {
						end = len(groups)
					}
					if err := database.BatchInsertGroup(ctx, groups[start:end]); err != nil {
						b.Fatal(err)
					}
				}
				if err := database.BatchInsertConversationList(ctx, rows); err != nil {
					b.Fatal(err)
				}
				listener := &stressConversationListener{}
				c := &Conversation{db: database, ConversationListener: func() open_im_sdk_callback.OnConversationListener { return listener }}
				runtime.GC()
				var before, after runtime.MemStats
				runtime.ReadMemStats(&before)
				b.ResetTimer()
				for turn := 0; turn < b.N; turn++ {
					if err := c.reconcileGroupConversationProfiles(ctx); err != nil {
						b.Fatal(err)
					}
				}
				b.StopTimer()
				runtime.ReadMemStats(&after)
				b.ReportMetric(float64(after.TotalAlloc-before.TotalAlloc)/1024/1024/float64(b.N), "alloc-MiB/op")
				b.ReportMetric(float64(after.HeapAlloc)/1024/1024, "end-heap-MiB")
				b.ReportMetric(float64(listener.bytes)/1024/1024, "callback-MiB")
				b.ReportMetric(float64(listener.largest), "largest-callback-rows")
				expected := 0
				if changed {
					expected = size
				}
				if listener.count != expected {
					b.Fatalf("lost refresh: %d/%d", listener.count, expected)
				}
				for i := 0; i < size; i++ {
					row, err := database.GetConversation(ctx, rows[i].ConversationID)
					if err != nil || row.ShowName != "After" || row.FaceURL != "new" || row.UnreadCount != 7 || row.DraftText != "draft" {
						b.Fatalf("incorrect group %d: %+v %v", i, row, err)
					}
				}
			})
		}
	}
}
