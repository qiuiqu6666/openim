//go:build cgo && !js

package db

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestMessageSyncBatchRollsBackRowsWhenConversationWriteFails(t *testing.T) {
	ctx := context.Background()
	d, err := NewDataBase(ctx, "atomic-test", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(ctx) })
	if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", UnreadCount: 3, LatestMsg: "before", LatestMsgSendTime: 3}}); err != nil {
		t.Fatal(err)
	}
	rows := map[string][]*model_struct.LocalChatLog{"chat": {{ClientMsgID: "m4", Seq: 4}}}
	// Updating an absent conversation fails after the message insert executed.
	err = d.CommitMessageSyncBatch(ctx, nil, rows, []*model_struct.LocalConversation{{ConversationID: "missing", UnreadCount: 4}}, nil)
	if err == nil {
		t.Fatal("injected conversation failure accepted")
	}
	if _, err = d.GetMessageBySeq(ctx, "chat", 4); err == nil {
		t.Fatal("message survived failed transaction")
	}
	if err = d.CommitMessageSyncBatch(ctx, nil, rows, []*model_struct.LocalConversation{{ConversationID: "chat", UnreadCount: 4, LatestMsg: "after", LatestMsgSendTime: 4}}, nil); err != nil {
		t.Fatal(err)
	}
	if _, err = d.GetMessageBySeq(ctx, "chat", 4); err != nil {
		t.Fatal(err)
	}
	c, err := d.GetConversation(ctx, "chat")
	if err != nil || c.UnreadCount != 4 || c.LatestMsg != "after" {
		t.Fatalf("partial commit: %+v %v", c, err)
	}
	if err = d.CommitMessageSyncBatch(ctx, nil, rows, nil, nil); err != nil {
		t.Fatal("replay not idempotent", err)
	}
}
