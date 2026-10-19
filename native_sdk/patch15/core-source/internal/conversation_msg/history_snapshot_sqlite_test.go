//go:build cgo && !js

package conversation_msg

import (
	"context"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

func TestLocalSnapshotSurvivesDatabaseReopenSQLite(t *testing.T) {
	_, _, _, cmd := recoveryConversation(t)
	dir := t.TempDir()
	d, err := db.NewDataBase(cmd.Ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsg: "{}", UnreadCount: 7}}); err != nil {
		t.Fatal(err)
	}
	var rows []*model_struct.LocalChatLog
	for i := 1; i <= 40; i++ {
		rows = append(rows, &model_struct.LocalChatLog{ClientMsgID: time.Unix(int64(i), 0).String(), Seq: int64(i), SendTime: int64(i), ContentType: constant.Text, Content: `{"content":"test"}`, AttachedInfo: "{}", Status: constant.MsgStatusSendSuccess})
	}
	if err := d.BatchInsertMessageList(cmd.Ctx, "chat", rows); err != nil {
		t.Fatal(err)
	}
	if err := d.Close(context.Background()); err != nil {
		t.Fatal(err)
	}
	d, err = db.NewDataBase(cmd.Ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	c := &Conversation{db: d}
	start := time.Now()
	page, err := c.getAdvancedHistoryMessageList(cmd.Ctx, sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 40, LocalSnapshot: true}, false)
	if err != nil || len(page.MessageList) != 40 || !page.LocalSnapshot || !page.SnapshotReady || page.IsEnd {
		t.Fatalf("cold snapshot: %+v %v", page, err)
	}
	t.Logf("reopened SQLite, 40 local messages, no network: %s", time.Since(start))
	conversation, err := d.GetConversation(cmd.Ctx, "chat")
	if err != nil || conversation.UnreadCount != 7 {
		t.Fatal("snapshot changed unread count")
	}
}
