//go:build cgo && !js

package db

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestReadWindowKeepsLocalRecordsInTimeBoundary(t *testing.T) {
	ctx := context.Background()
	d, err := NewDataBase(ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", MaxSeq: 1}}); err != nil {
		t.Fatal(err)
	}
	rows := []*model_struct.LocalChatLog{
		{ClientMsgID: "server", Seq: 1, SendTime: 100, Status: constant.MsgStatusSendSuccess},
		{ClientMsgID: "call", SendTime: 200, Status: constant.MsgStatusSendSuccess},
		{ClientMsgID: "old", SendTime: 50, Status: constant.MsgStatusSendSuccess},
	}
	if err = d.BatchInsertMessageList(ctx, "chat", rows); err != nil {
		t.Fatal(err)
	}
	w, err := d.ReadMessageWindow(ctx, "chat", 40, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(w.Rows) != 2 || w.Rows[1].ClientMsgID != "call" {
		t.Fatalf("local record lost: %+v", w.Rows)
	}
}
