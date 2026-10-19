//go:build !js && cgo

package db

import (
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"testing"
)

func TestRecoverySnapshotsAreAccountLocalAndPreserveVisibility(t *testing.T) {
	d, ctx := versionSyncTestDB(t)
	for _, row := range []*model_struct.LocalVersionSync{
		{Table: "sdk_message_coverage_v1", EntityID: "conversation:chat", VersionID: `{"completed":3,"target":20}`},
		{Table: "unrelated", EntityID: "conversation:chat", VersionID: "leave unchanged"},
	} {
		if err := d.SetVersionSync(ctx, row); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.InsertConversation(ctx, &model_struct.LocalConversation{ConversationID: "chat", MinSeq: 6, MaxSeq: 15, LatestMsgSendTime: 99, IsPinned: true, UnreadCount: 7}); err != nil {
		t.Fatal(err)
	}
	rows, err := d.GetMessageRecoveryVersions(ctx, "sdk_message_coverage_v1")
	if err != nil || len(rows) != 1 || rows[0].VersionID != `{"completed":3,"target":20}` {
		t.Fatalf("checkpoint snapshot: %v %v", rows, err)
	}
	bounds, err := d.GetMessageRecoveryBounds(ctx)
	if err != nil || len(bounds) != 1 || bounds[0].MinSeq != 6 || bounds[0].MaxSeq != 15 || bounds[0].LatestMsgSendTime != 99 || !bounds[0].IsPinned {
		t.Fatalf("boundary snapshot: %v %v", bounds, err)
	}
	conversation, err := d.GetConversation(ctx, "chat")
	if err != nil || conversation.UnreadCount != 7 {
		t.Fatal("snapshot changed unread state")
	}
}
