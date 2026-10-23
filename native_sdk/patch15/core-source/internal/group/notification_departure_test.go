package group

import (
	"context"
	"encoding/json"
	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	protocol "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
	"net/http"
	"testing"
)

func TestOfflineNotificationPermissionRecovery(t *testing.T) {
	for _, mode := range []string{"departed", "still_joined", "membership_failure", "transient", "storage_failure", "cancelled", "rejoined"} {
		t.Run(mode, func(t *testing.T) {
			batches, checks := 0, 0
			var cancel context.CancelFunc
			ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/group/get_full_join_group_ids" {
					checks++
					if mode == "membership_failure" {
						_ = json.NewEncoder(w).Encode(map[string]any{"errCode": 500, "errMsg": "unavailable"})
						return
					}
					if mode == "cancelled" {
						cancel()
						return
					}
					ids := []string{"valid"}
					if mode == "still_joined" || mode == "rejoined" {
						ids = append(ids, "old")
					}
					profileResponse(w, map[string]any{"groupIDs": ids})
					return
				}
				var req protocol.BatchGetIncrementalGroupMemberReq
				if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
					t.Error(err)
					return
				}
				batches++
				for _, item := range req.ReqList {
					if item.GroupID == "old" {
						code := 1002
						if mode == "transient" {
							code = 500
						}
						_ = json.NewEncoder(w).Encode(map[string]any{"errCode": code, "errMsg": "denied"})
						return
					}
				}
				profileResponse(w, map[string]any{"respList": map[string]any{"valid": map[string]any{}}})
			})
			ctx = common.WithMetadataProgress(ctx, &common.MetadataProgress{})
			ctx, cancel = context.WithCancel(ctx)
			defer cancel()
			d := &departureDB{rows: []*model_struct.LocalGroup{{GroupID: "old"}, {GroupID: "valid"}}, fail: mode == "storage_failure"}
			g := NewGroup("self", d, make(chan common.Cmd2Value, 4))
			l := &departureListener{}
			g.SetGroupListener(func() open_im_sdk_callback.OnGroupListener { return l })
			detail, _ := json.Marshal(&sdkws.GroupInfoSetTips{Group: &sdkws.GroupInfo{GroupID: "old"}, GroupMemberVersion: 3, GroupMemberVersionID: "remote"})
			content, _ := json.Marshal(map[string]string{"detail": string(detail)})
			notification := &sdkws.MsgData{ContentType: constant.GroupInfoSetNotification, Content: content, Seq: 1}
			err := g.DoNotification(ctx, notification)
			if mode == "departed" {
				if err != nil || batches != 1 || checks != 1 || d.deleted != 1 || l.removed != 1 || len(d.rows) != 1 || d.rows[0].GroupID != "valid" || d.invalidated != 2 {
					t.Fatalf("err=%v batches=%d checks=%d db=%+v listener=%+v", err, batches, checks, d, l)
				}
				// A subsequent local-list sweep must not recreate the retired job.
				if err := g.IncrSyncJoinGroupMember(ctx); err != nil || checks != 1 {
					t.Fatalf("retired job repeated: %v checks=%d", err, checks)
				}
			} else {
				if err == nil || d.deleted != 0 || l.removed != 0 || batches != 1 {
					t.Fatalf("unsafe retirement: err=%v batches=%d db=%+v", err, batches, d)
				}
				if mode == "transient" && checks != 0 {
					t.Fatal("transient error caused membership cleanup")
				}
				if mode != "cancelled" && len(common.PendingMetadataItems(ctx, "group-members", []string{"old", "valid"})) != 2 {
					t.Fatal("failed recovery acknowledged pending work")
				}
				if mode == "storage_failure" {
					d.fail = false
					if err := g.DoNotification(ctx, notification); err != nil || d.deleted != 1 || l.removed != 1 {
						t.Fatalf("storage retry failed: %v", err)
					}
				}
			}
		})
	}
}
