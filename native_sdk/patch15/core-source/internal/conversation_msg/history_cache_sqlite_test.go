//go:build cgo && !js

package conversation_msg

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"testing"
)

func TestLatestPrefetchThenLivePushCountsUnreadOnceSQLite(t *testing.T) {
	for _, tc := range []struct {
		name                      string
		maxSeq                    int64
		isRead                    bool
		initialUnread, wantUnread int32
		wantCallbacks             int
	}{
		{"prefetch before first delivery", 5, false, 0, 1, 1},
		{"already counted by server", 6, false, 1, 1, 0},
		{"already read", 6, true, 0, 0, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, _, callbacks, cmd := recoveryConversation(t)
			d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = d.Close(context.Background()) })
			c.db = d
			c.maxSeqRecorder.Set("chat", tc.maxSeq)
			if err := d.InsertLoginUser(cmd.Ctx, &model_struct.LocalUser{UserID: "self"}); err != nil {
				t.Fatal(err)
			}
			if err := d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsg: "{}", LatestMsgSendTime: 1, UnreadCount: tc.initialUnread}}); err != nil {
				t.Fatal(err)
			}
			rows := []*model_struct.LocalChatLog{{ClientMsgID: "m6", Seq: 6, SendTime: 6, SendID: "other", RecvID: "self", SessionType: constant.SingleChatType, ContentType: constant.Text, Content: `{"content":"hello"}`, Status: constant.MsgStatusSendSuccess, IsRead: tc.isRead}}
			var list []*model_struct.LocalChatLog
			if err := c.pullMessageIntoTable(cmd.Ctx, "chat", rows, &list); err != nil {
				t.Fatal(err)
			}
			input := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
			input.Recovery = true
			cmd.Value = input
			for n := 0; n < 2; n++ {
				if err := c.doMsgNew(cmd); err != nil {
					t.Fatal(err)
				}
				conv, err := d.GetConversation(cmd.Ctx, "chat")
				if err != nil || conv.UnreadCount != tc.wantUnread || callbacks.received != tc.wantCallbacks {
					t.Fatalf("delivery %d: unread=%+v callbacks=%d error=%v", n, conv, callbacks.received, err)
				}
			}
		})
	}
}

func TestOverlappingHistoryIsIdempotentAndPreservesLocalDeletionSQLite(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	c.db = d
	if err := d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", UnreadCount: 900, LatestMsg: `{"seq":1000}`}}); err != nil {
		t.Fatal(err)
	}
	if err := d.BatchInsertMessageList(cmd.Ctx, "chat", []*model_struct.LocalChatLog{{ClientMsgID: "m900", Seq: 900, SendTime: 900, SendID: "peer", Status: constant.MsgStatusHasDeleted}}); err != nil {
		t.Fatal(err)
	}
	for n := 0; n < 4; n++ {
		rows := []*model_struct.LocalChatLog{
			{ClientMsgID: "m900", Seq: 900, SendTime: 900, SendID: "peer", Status: constant.MsgStatusSendSuccess},
			{ClientMsgID: "m901", Seq: 901, SendTime: 901, SendID: "peer", Status: constant.MsgStatusSendSuccess},
		}
		var list []*model_struct.LocalChatLog
		if err := c.pullMessageIntoTable(cmd.Ctx, "chat", rows, &list); err != nil {
			t.Fatal(err)
		}
		if rows[0].Status != constant.MsgStatusHasDeleted || rows[0].ClientMsgID != "m900" || rows[1].ClientMsgID != "m901" {
			t.Fatalf("replay changed state/identity: %+v %+v", rows[0], rows[1])
		}
	}
	rows, err := d.GetMessageList(cmd.Ctx, "chat", 100, 0, 0, "", false)
	if err != nil || len(rows) != 2 {
		t.Fatalf("history grew duplicate rows: %d %v", len(rows), err)
	}
	conv, err := d.GetConversation(cmd.Ctx, "chat")
	if err != nil || conv.UnreadCount != 900 {
		t.Fatalf("history changed unread: %+v %v", conv, err)
	}
}

func TestRecallBeforeOriginalArrivesIsDurableSQLite(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	c.db = d
	listener := &revokeRecoveryListener{}
	c.msgListener = func() open_im_sdk_callback.OnAdvancedMsgListener { return listener }
	if err := d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", UnreadCount: 3, LatestMsg: `{"seq":1000}`}}); err != nil {
		t.Fatal(err)
	}
	// Create an empty table: there is no body for the historical seq 10.
	if err := d.BatchInsertMessageList(cmd.Ctx, "chat", nil); err != nil {
		t.Fatal(err)
	}
	if err := c.revokeMessage(cmd.Ctx, &sdkws.RevokeMsgTips{ConversationID: "chat", Seq: 10, RevokerUserID: "peer"}); err != nil {
		t.Fatal(err)
	}
	rows := []*model_struct.LocalChatLog{{ClientMsgID: "old", Seq: 10, SendID: "peer", Status: constant.MsgStatusSendSuccess, ContentType: constant.Text, Content: `{"content":"original"}`}}
	var list []*model_struct.LocalChatLog
	if err := c.pullMessageIntoTable(cmd.Ctx, "chat", rows, &list); err != nil {
		t.Fatal(err)
	}
	if rows[0].ContentType != constant.RevokeNotification {
		t.Fatal("history resurrected recalled content")
	}
	row, err := d.GetMessageBySeq(cmd.Ctx, "chat", 10)
	if err != nil || row.ContentType != constant.RevokeNotification {
		t.Fatalf("stored recall lost: %+v %v", row, err)
	}
}

func TestSparseGroupReadReceiptDoesNotClearNewerUnreadSQLite(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	c.db = d
	c.maxSeqRecorder.Set("chat", 1000)
	if err := d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.ReadGroupChatType, UnreadCount: 900, LatestMsg: `{"seq":1000}`, LatestMsgSendTime: 1000}}); err != nil {
		t.Fatal(err)
	}
	for _, seq := range []int64{900, 500} {
		if err := c.doReadDrawing(cmd.Ctx, watermarkNotice("self", seq)); err != nil {
			t.Fatal(err)
		}
		conv, err := d.GetConversation(cmd.Ctx, "chat")
		if err != nil || conv.UnreadCount != 100 {
			t.Fatalf("sparse/stale read changed unread: %+v %v", conv, err)
		}
	}
}
