//go:build cgo && !js

package conversation_msg

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

func TestMessageSyncAtomicSelfAckPreservesPayloadSQLite(t *testing.T) {
	c, _, callbacks, cmd := selfMessageLossFixture(t)
	d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	if err = d.InsertLoginUser(cmd.Ctx, &model_struct.LocalUser{UserID: "self"}); err != nil {
		t.Fatal(err)
	}
	preview := &sdk_struct.MsgStruct{ClientMsgID: "m6", Seq: 0, SendTime: 1001}
	if err = d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsg: utils.StructToJsonString(preview), LatestMsgSendTime: 1001}}); err != nil {
		t.Fatal(err)
	}
	if err = d.BatchInsertMessageList(cmd.Ctx, "chat", []*model_struct.LocalChatLog{{ClientMsgID: "m6", SendID: "self", Seq: 0, SendTime: 1001, Status: constant.MsgStatusSending, Content: "local payload", LocalEx: "local extension"}}); err != nil {
		t.Fatal(err)
	}
	c.db = d
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	row, err := d.GetMessageBySeq(cmd.Ctx, "chat", 1000)
	if err != nil {
		t.Fatal(err)
	}
	if row.Content != "local payload" || row.LocalEx != "local extension" || row.Status != constant.MsgStatusSendSuccess {
		t.Fatalf("ack overwrote local data: %+v", row)
	}
	conv, err := d.GetConversation(cmd.Ctx, "chat")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal([]byte(conv.LatestMsg), preview); err != nil {
		t.Fatal(err)
	}
	if preview.Seq != 1000 || callbacks.received != 0 {
		t.Fatalf("ack preview=%d duplicate callback=%d", preview.Seq, callbacks.received)
	}
}
