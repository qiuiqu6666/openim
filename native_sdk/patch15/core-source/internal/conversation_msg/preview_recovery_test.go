package conversation_msg

import (
	"context"
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"testing"
)

func TestEqualTimePreviewUsesServerSequence(t *testing.T) {
	row := func(seq int64) *model_struct.LocalConversation {
		return &model_struct.LocalConversation{LatestMsgSendTime: 100, LatestMsg: fmt.Sprintf(`{"seq":%d}`, seq)}
	}
	if !newerConversationPreview(row(205), row(204)) {
		t.Fatal("latest equal-time message was discarded")
	}
	if newerConversationPreview(row(204), row(205)) {
		t.Fatal("preview regressed")
	}
	if newerConversationPreview(row(205), row(0)) {
		t.Fatal("unsent preview was replaced")
	}
	c := &Conversation{}
	rows := map[string]*model_struct.LocalConversation{"chat": row(204)}
	n := row(205)
	n.ConversationID = "chat"
	c.updateConversation(n, rows)
	if rows["chat"].LatestMsg != n.LatestMsg {
		t.Fatal("batch merge lost equal-time latest message")
	}
}

type tiedPreviewDB struct {
	db_interface.DataBase
	latest *model_struct.LocalChatLog
	writes int
}

func (d *tiedPreviewDB) GetLatestActiveMessage(context.Context, string, bool) ([]*model_struct.LocalChatLog, error) {
	return []*model_struct.LocalChatLog{d.latest}, nil
}
func (d *tiedPreviewDB) UpdateColumnsConversation(context.Context, string, map[string]interface{}) error {
	d.writes++
	return nil
}
func TestPersistedTieRepairPreservesHiddenAndPendingRows(t *testing.T) {
	db := &tiedPreviewDB{latest: &model_struct.LocalChatLog{ClientMsgID: "latest", Seq: 205, SendTime: 100, ContentType: 101, Content: `{"content":"test"}`, Status: 2}}
	c := &Conversation{db: db}
	rows := []*model_struct.LocalConversation{
		{ConversationID: "visible", LatestMsgSendTime: 100, LatestMsg: `{"seq":204}`},
		{ConversationID: "hidden", LatestMsgSendTime: 0, LatestMsg: `{"seq":204}`},
		{ConversationID: "pending", LatestMsgSendTime: 100, LatestMsg: `{"seq":0}`},
	}
	if err := c.repairTiedPreviews(context.Background(), rows); err != nil {
		t.Fatal(err)
	}
	if db.writes != 1 {
		t.Fatalf("writes=%d", db.writes)
	}
	if !newerConversationPreview(rows[0], &model_struct.LocalConversation{LatestMsgSendTime: 100, LatestMsg: `{"seq":204}`}) {
		t.Fatal("persisted preview not repaired")
	}
	if err := c.repairTiedPreviews(context.Background(), rows); err != nil {
		t.Fatal(err)
	}
	if db.writes != 1 {
		t.Fatal("repair is not idempotent")
	}
}
