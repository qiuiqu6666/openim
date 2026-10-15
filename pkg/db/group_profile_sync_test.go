//go:build cgo && !js

package db

import (
	"context"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestGroupProfilePagesAreCompleteAndRollbackOnFailure(t *testing.T) {
	ctx := ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{UserID: "profile-pages"})
	d, err := NewDataBase(ctx, "profile-pages", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	groups := make([]*model_struct.LocalGroup, 257)
	rows := make([]*model_struct.LocalConversation, 257)
	for i := range groups {
		id := fmt.Sprintf("g%04d", i)
		face := "new"
		if i%7 == 0 {
			face = ""
		}
		groups[i] = &model_struct.LocalGroup{GroupID: id, GroupName: "New", FaceURL: face}
		rows[i] = &model_struct.LocalConversation{ConversationID: id, GroupID: id, ConversationType: constant.ReadGroupChatType, ShowName: "Old", FaceURL: "old", LatestMsgSendTime: 1, DraftText: "draft", UnreadCount: 7, IsPinned: true}
	}
	for start := 0; start < len(groups); start += 100 {
		end := start + 100
		if end > len(groups) {
			end = len(groups)
		}
		if err := d.BatchInsertGroup(ctx, groups[start:end]); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.BatchInsertConversationList(ctx, rows); err != nil {
		t.Fatal(err)
	}
	if err := d.conn.Exec("CREATE TRIGGER fail_profile BEFORE UPDATE ON local_conversations WHEN OLD.conversation_id = 'g0002' BEGIN SELECT RAISE(ABORT, 'injected profile failure'); END").Error; err != nil {
		t.Fatal(err)
	}
	if _, err := d.ReconcileGroupConversationProfilePage(ctx, "", 128); err == nil {
		t.Fatal("write failure was swallowed")
	}
	first, err := d.GetConversation(ctx, "g0000")
	if err != nil || first.ShowName != "Old" {
		t.Fatal("failed page did not roll back")
	}
	if err := d.conn.Exec("DROP TRIGGER fail_profile").Error; err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	after := ""
	for {
		page, err := d.ReconcileGroupConversationProfilePage(ctx, after, 128)
		if err != nil {
			t.Fatal(err)
		}
		if len(page) == 0 {
			break
		}
		if len(page) > 128 {
			t.Fatal("unbounded callback page")
		}
		for _, row := range page {
			if seen[row.ConversationID] || row.ShowName != "New" || row.UnreadCount != 7 || row.DraftText != "draft" || !row.IsPinned {
				t.Fatalf("incorrect page row %+v", row)
			}
			seen[row.ConversationID] = true
		}
		after = page[len(page)-1].ConversationID
	}
	if len(seen) != len(groups) {
		t.Fatalf("lost group profiles: %d/%d", len(seen), len(groups))
	}
	for _, group := range groups {
		row, err := d.GetConversation(ctx, group.GroupID)
		if err != nil || row.FaceURL != group.FaceURL {
			t.Fatalf("avatar missed: %s", group.GroupID)
		}
	}
	page, err := d.ReconcileGroupConversationProfilePage(ctx, "", 128)
	if err != nil || len(page) != 0 {
		t.Fatal("unchanged data was republished")
	}
}
