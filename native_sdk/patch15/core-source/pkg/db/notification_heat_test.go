package db

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func TestNotificationQueriesExcludeTombstonesAndAllowReadReplay(t *testing.T) {
	ctx := context.Background()
	d, err := NewDataBase(ctx, "heat-receipt", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(ctx) })
	const id = "si_heat"
	if err := d.BatchInsertMessageList(ctx, id, []*model_struct.LocalChatLog{
		{ClientMsgID: "live", Seq: 1, SendID: "peer", Status: constant.MsgStatusSendSuccess, ContentType: constant.Quote, Content: `{}`},
		{ClientMsgID: "deleted", Seq: 2, SendID: "peer", Status: constant.MsgStatusHasDeleted, ContentType: constant.Quote},
		{ClientMsgID: "own", Seq: 3, SendID: "heat-receipt", Status: constant.MsgStatusSendSuccess},
	}); err != nil {
		t.Fatal(err)
	}
	quotes, err := d.SearchAllMessageByContentType(ctx, id, constant.Quote)
	if err != nil || len(quotes) != 1 || quotes[0].ClientMsgID != "live" {
		t.Fatalf("deleted quote included: %+v, %v", quotes, err)
	}
	for _, seqs := range [][]int64{{3995, 3999}, {3}, {1}, {1}, {2}, {}} {
		if _, err := d.MarkConversationMessageAsReadBySeqs(ctx, id, seqs); err != nil {
			t.Fatalf("read replay/no cached rows failed: %v", err)
		}
	}
	deleted, err := d.GetMessageBySeq(ctx, id, 2)
	if err != nil || deleted.IsRead {
		t.Fatalf("changed deleted row: %+v %v", deleted, err)
	}
	if _, err := d.MarkConversationMessageAsReadBySeqs(ctx, "si_missing_table", []int64{1}); err == nil {
		t.Fatal("database failure was hidden as a no-op")
	}
}
