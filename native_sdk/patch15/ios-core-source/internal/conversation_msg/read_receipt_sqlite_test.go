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

func TestReadReceiptPageSQLiteMissingTerminal(t *testing.T) {
	for _, explicit := range []bool{false, true} {
		t.Run(map[bool]string{false: "empty-seqs", true: "explicit-seqs"}[explicit], func(t *testing.T) {
			c, _, _ := watermarkFixture()
			ctx := context.Background()
			d, err := db.NewDataBase(ctx, "self", t.TempDir(), 0)
			if err != nil {
				t.Fatal(err)
			}
			defer d.Close(ctx)
			c.db = d
			conv := &model_struct.LocalConversation{ConversationID: "chat", ConversationType: constant.SingleChatType, UnreadCount: 3, LatestMsg: `{"clientMsgID":"own","sendID":"self","seq":4}`, LatestMsgSendTime: 1}
			if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{conv}); err != nil {
				t.Fatal(err)
			}
			if err = d.BatchInsertMessageList(ctx, "chat", []*model_struct.LocalChatLog{{ClientMsgID: "peer", Seq: 1, SendID: "peer"}, {ClientMsgID: "own", Seq: 4, SendID: "self"}}); err != nil {
				t.Fatal(err)
			}
			for _, seq := range []int64{8, 2} {
				tips := &sdkws.MarkAsReadTips{ConversationID: "chat", MarkAsReadUserID: "self", HasReadSeq: seq}
				if explicit {
					tips.Seqs = []int64{1, seq}
				}
				n := &sdkws.MsgData{ContentType: constant.HasReadReceipt, Seq: 101, Content: []byte(utils.StructToJsonString(sdk_struct.NotificationElem{Detail: utils.StructToJsonString(tips)}))}
				cmd := common.Cmd2Value{Ctx: ctx, Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_chat": {Msgs: []*sdkws.MsgData{n}}}}}
				if err = c.doNotificationManager(cmd); err != nil {
					t.Fatal(err)
				}
			}
			peer, err := d.GetMessageBySeq(ctx, "chat", 1)
			if err != nil || !peer.IsRead {
				t.Fatalf("peer read lost: %+v %v", peer, err)
			}
			own, err := d.GetMessageBySeq(ctx, "chat", 4)
			if err != nil || own.IsRead {
				t.Fatalf("self receipt marked own message: %+v %v", own, err)
			}
			stored, err := d.GetConversation(ctx, "chat")
			if err != nil || stored.UnreadCount != 1 {
				t.Fatalf("stale receipt corrupted unread: %+v %v", stored, err)
			}
			seqs, err := d.GetNotificationAllSeqs(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if len(seqs) != 1 || seqs[0].ConversationID != "n_chat" || seqs[0].Seq != 101 {
				t.Fatalf("notification cursor not committed: %v", seqs)
			}
		})
	}
}
