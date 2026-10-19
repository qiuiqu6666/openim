//go:build cgo && !js

package conversation_msg

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func TestColdGroupReceiptDoesNotBlockNotificationPage(t *testing.T) {
	ctx := context.Background()
	store, err := db.NewDataBase(ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close(ctx) })
	const id = "sg_@lg_cold_receipt"
	if err := store.InsertConversation(ctx, &model_struct.LocalConversation{
		ConversationID: id, ConversationType: constant.ReadGroupChatType,
	}); err != nil {
		t.Fatal(err)
	}
	c, _, _ := watermarkFixture()
	c.db = store
	tips := &sdkws.MarkAsReadTips{ConversationID: id, MarkAsReadUserID: "peer", Seqs: []int64{1, 2}}
	msg := &sdkws.MsgData{Seq: 57, ContentType: constant.HasReadReceipt, SendTime: 1234,
		Content: []byte(utils.StructToJsonString(sdk_struct.NotificationElem{Detail: utils.StructToJsonString(tips)}))}
	const notificationID = "n_@lg_cold_receipt"
	cmd := common.Cmd2Value{Ctx: ctx, Value: sdk_struct.CmdNewMsgComeToConversation{
		Msgs: map[string]*sdkws.PullMsgs{notificationID: {Msgs: []*sdkws.MsgData{msg}}},
	}}
	for attempt := 0; attempt < 2; attempt++ {
		if err := c.doNotificationManager(cmd); err != nil {
			t.Fatal(err)
		}
		seqs, err := store.GetNotificationAllSeqs(ctx)
		if err != nil || len(seqs) != 1 || seqs[0].ConversationID != notificationID || seqs[0].Seq != 57 {
			t.Fatalf("receipt blocked: seqs=%v err=%v", seqs, err)
		}
	}
}
