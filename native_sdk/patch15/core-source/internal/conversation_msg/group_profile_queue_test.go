//go:build cgo && !js

package conversation_msg

import (
	"context"
	"fmt"
	"testing"

	groups "github.com/openimsdk/openim-sdk-core/v3/internal/group"
	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestQueuedGroupProfileDoesNotRepublishReconciledRows(t *testing.T) {
	ctx := ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{UserID: "self"})
	d, err := db.NewDataBase(ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	groupRows := make([]*model_struct.LocalGroup, 257)
	rows := make([]*model_struct.LocalConversation, 257)
	for i := range rows {
		id := fmt.Sprintf("g%04d", i)
		groupRows[i] = &model_struct.LocalGroup{GroupID: id, GroupName: "New", FaceURL: "new", GroupType: constant.SuperGroup}
		rows[i] = &model_struct.LocalConversation{ConversationID: "sg_" + id, GroupID: id, ConversationType: constant.ReadGroupChatType, ShowName: "Old", FaceURL: "old", LatestMsgSendTime: 1, UnreadCount: 7, DraftText: "draft"}
	}
	for start := 0; start < len(rows); start += 100 {
		end := start + 100
		if end > len(rows) {
			end = len(rows)
		}
		if err := d.BatchInsertGroup(ctx, groupRows[start:end]); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.BatchInsertConversationList(ctx, rows); err != nil {
		t.Fatal(err)
	}
	listener := &stressConversationListener{}
	c := &Conversation{db: d, group: groups.NewGroup("self", d, make(chan common.Cmd2Value, 1)), loginUserID: "self", ConversationListener: func() open_im_sdk_callback.OnConversationListener { return listener }}
	if err := c.reconcileGroupConversationProfiles(ctx); err != nil {
		t.Fatal(err)
	}
	if listener.count != len(rows) {
		t.Fatal("reconciliation missed groups")
	}
	for _, row := range rows {
		c.doUpdateConversation(common.Cmd2Value{Ctx: ctx, Value: common.UpdateConNode{Action: constant.UpdateConFaceUrlAndNickName, Args: common.SourceIDAndSessionType{SourceID: row.GroupID, SessionType: constant.ReadGroupChatType, Nickname: "New", FaceURL: "new"}}})
	}
	if listener.count != len(rows) {
		t.Fatal("queued profiles duplicated bulk refresh")
	}
	// A later real online avatar removal must still update and notify once.
	c.doUpdateConversation(common.Cmd2Value{Ctx: ctx, Value: common.UpdateConNode{Action: constant.UpdateConFaceUrlAndNickName, Args: common.SourceIDAndSessionType{SourceID: rows[0].GroupID, SessionType: constant.ReadGroupChatType, Nickname: "New", FaceURL: ""}}})
	actual, err := d.GetConversation(ctx, rows[0].ConversationID)
	if err != nil || actual.FaceURL != "" || actual.UnreadCount != 7 || actual.DraftText != "draft" || listener.count != len(rows)+1 {
		t.Fatalf("online avatar removal lost: %+v err=%v callbacks=%d", actual, err, listener.count)
	}
}
