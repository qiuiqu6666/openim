//go:build cgo && !js

package conversation_msg

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

// Seed the legacy persisted shape, close the database, then read it through
// the new SDK window path. No resend, backfill or database rewrite is needed.
func TestWindowUpgradeRecoversPersistedCallRecords(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	d, err := db.NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	conversation := &model_struct.LocalConversation{ConversationID: "chat", MaxSeq: 1, UnreadCount: 3, LatestMsg: "{}"}
	if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{conversation}); err != nil {
		t.Fatal(err)
	}
	const callContent = `{"data":"{\"customType\":901,\"data\":{\"type\":\"audio\",\"state\":\"cancel\",\"duration\":0}}","extension":"","description":""}`
	rows := []*model_struct.LocalChatLog{
		{ClientMsgID: "server", Seq: 1, SendTime: 100, Status: constant.MsgStatusSendSuccess, ContentType: constant.Text, Content: `{"content":"hello"}`, AttachedInfo: "{}"},
		{ClientMsgID: "legacy-call", Seq: 0, SendTime: 200, Status: constant.MsgStatusSendSuccess, ContentType: constant.Custom, Content: callContent, AttachedInfo: "{}", IsRead: true},
		{ClientMsgID: "deleted-call", Seq: 0, SendTime: 201, Status: constant.MsgStatusHasDeleted, ContentType: constant.Custom, Content: callContent, AttachedInfo: "{}"},
	}
	if err = d.BatchInsertMessageList(ctx, "chat", rows); err != nil {
		t.Fatal(err)
	}
	if err = d.Close(ctx); err != nil {
		t.Fatal(err)
	}
	d, err = db.NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	c := &Conversation{db: d}
	for attempt := 0; attempt < 3; attempt++ {
		p, err := c.messageWindow(ctx, sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 40, LocalSnapshot: true, Window: true})
		if err != nil {
			t.Fatal(err)
		}
		if !p.Window.Publishable || len(p.MessageList) != 2 || p.MessageList[1].ClientMsgID != "legacy-call" {
			t.Fatalf("upgrade failed to recover old call exactly once: %+v", p)
		}
		call := p.MessageList[1]
		if call.Seq != 0 || !call.IsRead || call.CustomElem == nil {
			t.Fatalf("legacy call metadata changed: %+v", call)
		}
	}
	stored, err := d.GetConversation(ctx, "chat")
	if err != nil {
		t.Fatal(err)
	}
	if stored.UnreadCount != 3 || stored.LatestMsg != "{}" {
		t.Fatal("recovery rewrote conversation state")
	}
	read, err := d.ReadMessageWindow(ctx, "chat", 40, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(read.Rows) != 3 {
		t.Fatal("recovery duplicated or removed stored messages")
	}
	for _, row := range read.Rows {
		if row.ClientMsgID == "legacy-call" && (row.Content != callContent || row.Seq != 0) {
			t.Fatal("recovery rewrote historical call")
		}
		if row.ClientMsgID == "deleted-call" && row.Status != constant.MsgStatusHasDeleted {
			t.Fatal("recovery resurrected deletion")
		}
	}
}
