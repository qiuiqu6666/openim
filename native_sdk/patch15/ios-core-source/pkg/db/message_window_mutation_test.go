//go:build cgo && !js

package db

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/sdkws"
	"testing"
)

func TestWindowMutationsSurviveStaleSnapshotAndReopen(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	d, err := NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", MaxSeq: 2}}); err != nil {
		t.Fatal(err)
	}
	rows := []*model_struct.LocalChatLog{{ClientMsgID: "m1", Seq: 1, SendID: "peer", ContentType: constant.Text, Content: `{"content":"old"}`, Status: constant.MsgStatusSendSuccess}, {ClientMsgID: "m2", Seq: 2, Status: constant.MsgStatusHasDeleted}}
	if err = d.BatchInsertMessageList(ctx, "chat", rows); err != nil {
		t.Fatal(err)
	}
	if err = d.SaveMessageRevocation(ctx, &sdkws.RevokeMsgTips{ConversationID: "chat", Seq: 1, RevokerUserID: "peer", RevokeTime: 10}); err != nil {
		t.Fatal(err)
	}
	// This response began before both the recall and deletion were committed.
	stale := []*model_struct.LocalChatLog{{ClientMsgID: "m1", Seq: 1, Status: constant.MsgStatusSendSuccess}, {ClientMsgID: "m2", Seq: 2, Status: constant.MsgStatusSendSuccess}}
	if err = d.CommitMessageSyncBatch(ctx, map[string][]*model_struct.LocalChatLog{"chat": stale}, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	if err = d.Close(ctx); err != nil {
		t.Fatal(err)
	}
	d, err = NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	w, err := d.ReadMessageWindow(ctx, "chat", 40, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(w.Rows) != 2 || w.Rows[0].Status != constant.MsgStatusHasDeleted || w.Rows[1].ContentType != constant.RevokeNotification {
		t.Fatalf("stale snapshot resurrected message: %+v", w.Rows)
	}
}
