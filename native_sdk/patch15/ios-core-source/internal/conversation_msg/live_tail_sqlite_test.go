//go:build cgo && !js

package conversation_msg

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestLiveTailAndOlderReplayPreserveUnreadAndLatestSQLite(t *testing.T) {
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
	// An authoritative server read/max snapshot already accounts for old
	// messages 6..1000, even though their local bodies are not all present.
	if err = d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsg: "{}", LatestMsgSendTime: 1, UnreadCount: 995}}); err != nil {
		t.Fatal(err)
	}
	c.db = d
	c.maxSeqRecorder.Set("chat", 1000)
	p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	p.Recovery = true
	latest := p.Msgs["chat"].Msgs[0]
	latest.ClientMsgID, latest.Seq, latest.SendTime = "live1001", 1001, 1001
	cmd.Value = p
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 1 {
		t.Fatal("latest arrival not delivered immediately")
	}
	// The same live message later appears again in full coverage replay.
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	older := proto.Clone(latest).(*sdkws.MsgData)
	older.ClientMsgID, older.Seq, older.SendTime = "old6", 6, 6
	p.Msgs["chat"].Msgs[0] = older
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
	var preview sdk_struct.MsgStruct
	if err = json.Unmarshal([]byte(row.LatestMsg), &preview); err != nil {
		t.Fatal(err)
	}
	if row.UnreadCount != 996 || preview.Seq != 1001 || callbacks.received != 2 {
		t.Fatalf("replay effects unread=%d latest=%d callbacks=%d", row.UnreadCount, preview.Seq, callbacks.received)
	}
	for _, seq := range []int64{6, 1001} {
		if _, err = d.GetMessageBySeq(cmd.Ctx, "chat", seq); err != nil {
			t.Fatal(err)
		}
	}
	if err = d.Close(cmd.Ctx); err != nil {
		t.Fatal(err)
	}
	d, err = db.NewDataBase(cmd.Ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	c, _, callbacks, _ = recoveryConversation(t)
	c.db = d
	c.maxSeqRecorder.Set("chat", 1001)
	p.Msgs["chat"].Msgs[0] = latest
	cmd.Value = p
	if err = c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	row, err = d.GetConversation(cmd.Ctx, "chat")
	if err != nil || row.UnreadCount != 996 || callbacks.received != 0 {
		t.Fatal("restart replay duplicated unread or arrival")
	}
}
