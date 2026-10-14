//go:build cgo && !js

package conversation_msg

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

type reviewUnreadFailDB struct {
	*db.DataBase
	fail bool
}

func (d *reviewUnreadFailDB) GetTotalUnreadMsgCountDB(ctx context.Context) (int32, error) {
	if d.fail {
		return 0, errors.New("injected unread-query failure after commit")
	}
	return d.DataBase.GetTotalUnreadMsgCountDB(ctx)
}

type deliveryCallbacks struct {
	*recoveryCallbacks
	unreadNotifications int
}

func (c *deliveryCallbacks) OnTotalUnreadMessageCountChanged(int32) { c.unreadNotifications++ }

func TestPeerDeliverySurvivesPostCommitFailureSQLite(t *testing.T) {
	c, _, callbacks, cmd := recoveryConversation(t)
	dir := t.TempDir()
	d, err := db.NewDataBase(cmd.Ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	if err = d.InsertLoginUser(cmd.Ctx, &model_struct.LocalUser{UserID: "self"}); err != nil {
		t.Fatal(err)
	}
	if err = d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsg: "{}", LatestMsgSendTime: 1}}); err != nil {
		t.Fatal(err)
	}
	wrapper := &reviewUnreadFailDB{DataBase: d, fail: true}
	c.db = wrapper
	if err = c.doMsgNew(cmd); err == nil {
		t.Fatal("expected injected post-commit failure")
	}
	if _, err = d.GetMessageBySeq(cmd.Ctx, "chat", 6); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 0 {
		t.Fatal("unexpected callback before failure")
	}
	// Drop both database handle and all in-memory delivery state, as on restart.
	if err = d.Close(cmd.Ctx); err != nil {
		t.Fatal(err)
	}
	d, err = db.NewDataBase(cmd.Ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	c, _, callbacks, _ = recoveryConversation(t)
	c.db = d
	c.maxSeqRecorder.Set("chat", 6) // Server read-sequence reconciliation already ran.
	listener := &deliveryCallbacks{recoveryCallbacks: callbacks}
	c.ConversationListener = func() open_im_sdk_callback.OnConversationListener { return listener }
	p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	p.Recovery = true
	cmd.Value = p
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	t.Logf("after success retry: peer callbacks=%d; row seq6 persisted", callbacks.received)
	if callbacks.received != 1 {
		t.Errorf("message persisted before failure must be delivered on successful recovery: got %d callbacks", callbacks.received)
	}
	if listener.unreadNotifications != 1 {
		t.Fatal("retry lost total unread notification")
	}
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 1 {
		t.Fatal("acknowledged recovery emitted a duplicate arrival")
	}
	conv, err := d.GetConversation(cmd.Ctx, "chat")
	if err != nil || conv.UnreadCount != 1 {
		t.Fatalf("recovery double-counted unread: %+v %v", conv, err)
	}
	pending, err := c.loadMessageDeliveries(cmd.Ctx, "chat")
	if err != nil || len(pending) != 0 {
		t.Fatalf("delivery obligation not acknowledged: %v %v", pending, err)
	}
}

func TestPeerDeliveryRepairsHiddenFallbackPartialWrite(t *testing.T) {
	c, d, callbacks, cmd := selfMessageLossFixture(t)
	p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	p.Msgs["chat"].Msgs[0].SendID = "other"
	p.Msgs["chat"].Msgs[0].RecvID = "self"
	p.Recovery = true
	cmd.Value = p
	d.conversation.LatestMsg = ""
	d.conversation.LatestMsgSendTime = 0
	d.conversationErr = errors.New("injected failure after message insert")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected injected partial failure")
	}
	if d.rows["m6"] == nil {
		t.Fatal("expected committed message")
	}
	d.conversationErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	t.Logf("after success retry: latest=%q time=%d callbacks=%d rows=%d", d.conversation.LatestMsg, d.conversation.LatestMsgSendTime, callbacks.received, len(d.rows))
	if d.conversation.LatestMsgSendTime == 0 || callbacks.received != 1 {
		t.Error("successful retry left hidden conversation and lost peer arrival")
	}
}

func TestSelfDeliveryJournalSurvivesLostMemory(t *testing.T) {
	c, d, callbacks, cmd := selfMessageLossFixture(t)
	d.conversationErr = errors.New("failed after message write")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected partial failure")
	}
	c.pendingSelfDeliveries = nil
	d.conversationErr = nil
	p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	p.Recovery = true
	cmd.Value = p
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 1 {
		t.Fatalf("lost cross-device self delivery: %d", callbacks.received)
	}
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 1 {
		t.Fatal("duplicate acknowledged self delivery")
	}
}

func TestPendingPeerDeliveryHonorsLocalDeletion(t *testing.T) {
	c, d, callbacks, cmd := selfMessageLossFixture(t)
	p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	p.Msgs["chat"].Msgs[0].SendID = "other"
	p.Msgs["chat"].Msgs[0].RecvID = "self"
	p.Recovery = true
	cmd.Value = p
	d.conversationErr = errors.New("failed after message write")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected partial failure")
	}
	d.rows["m6"].Status = constant.MsgStatusHasDeleted
	d.conversationErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 0 {
		t.Fatal("local deletion was resurrected by pending delivery")
	}
	pending, err := c.loadMessageDeliveries(cmd.Ctx, "chat")
	if err != nil || len(pending) != 0 {
		t.Fatal("deleted delivery remains pending")
	}
}
