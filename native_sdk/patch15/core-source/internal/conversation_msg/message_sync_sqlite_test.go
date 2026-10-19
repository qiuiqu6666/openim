//go:build cgo && !js

package conversation_msg

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

func TestRecoveredPeerReplayDoesNotDuplicateUnreadOrCallbacksSQLite(t *testing.T) {
	c, _, callbacks, cmd := recoveryConversation(t)
	d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	if err = d.InsertLoginUser(cmd.Ctx, &model_struct.LocalUser{UserID: "self"}); err != nil {
		t.Fatal(err)
	}
	if err = d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsg: "{}", LatestMsgSendTime: 1, UnreadCount: 1}}); err != nil {
		t.Fatal(err)
	}
	c.db = d
	// Prior page's authoritative read reconciliation already accounts for seq 6.
	c.maxSeqRecorder.Set("chat", 6)
	p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	p.Recovery = true
	cmd.Value = p
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	row, err := d.GetConversation(cmd.Ctx, "chat")
	if err != nil {
		t.Fatal(err)
	}
	if row.UnreadCount != 1 || callbacks.received != 1 {
		t.Fatalf("duplicate effects: unread=%d callbacks=%d", row.UnreadCount, callbacks.received)
	}
	if _, err = d.GetMessageBySeq(cmd.Ctx, "chat", 6); err != nil {
		t.Fatal(err)
	}
	// A local deletion remains deleted when legacy history is replayed.
	if err = d.UpdateMessageBySeq(cmd.Ctx, "chat", &model_struct.LocalChatLog{Seq: 6, Status: constant.MsgStatusHasDeleted}); err != nil {
		t.Fatal(err)
	}
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	deleted, err := d.GetMessageBySeq(cmd.Ctx, "chat", 6)
	if err != nil || deleted.Status != constant.MsgStatusHasDeleted || callbacks.received != 1 {
		t.Fatal("recovery resurrected a deleted row")
	}
}
