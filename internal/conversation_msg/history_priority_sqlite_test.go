//go:build cgo && !js

package conversation_msg

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"testing"
)

func TestPriorityHistoryReusesSQLiteRowsIncludingTombstones(t *testing.T) {
	_, _, _, cmd := recoveryConversation(t)
	d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	c := &Conversation{db: d}
	rows, err := c.localLatestHistoryRows(cmd.Ctx, "new-device-chat", []int64{1, 2, 3})
	if err != nil || len(rows) != 0 {
		t.Fatalf("new device without message table: %v %v", rows, err)
	}
	if err = d.BatchInsertMessageList(cmd.Ctx, "new-device-chat", []*model_struct.LocalChatLog{
		{ClientMsgID: "one", Seq: 1, Status: constant.MsgStatusSendSuccess},
		{ClientMsgID: "deleted", Seq: 3, Status: constant.MsgStatusHasDeleted},
	}); err != nil {
		t.Fatal(err)
	}
	rows, err = c.localLatestHistoryRows(cmd.Ctx, "new-device-chat", []int64{1, 2, 3})
	if err != nil || len(rows) != 2 {
		t.Fatalf("durable successful and deleted rows must both prevent repeat download: %v %v", rows, err)
	}
	for _, row := range rows {
		if row.Seq == 2 {
			t.Fatal("missing row falsely covered")
		}
	}
}
