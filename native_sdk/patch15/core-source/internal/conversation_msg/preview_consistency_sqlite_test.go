//go:build cgo && !js

package conversation_msg

import (
	"context"
	"encoding/json"
	"sync"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func TestPreviewConsistencySQLite(t *testing.T) {
	for _, mode := range []string{"query", "history", "clock reversal", "deleted", "filtered", "revoked", "pending", "failed", "hidden", "cleared", "private", "visibility"} {
		t.Run(mode, func(t *testing.T) {
			c, _, callbacks, cmd := recoveryConversation(t)
			d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = d.Close(context.Background()) })
			c.db = d
			if err := d.InsertLoginUser(cmd.Ctx, &model_struct.LocalUser{UserID: "self"}); err != nil {
				t.Fatal(err)
			}
			old := &sdk_struct.MsgStruct{ClientMsgID: "m998", Seq: 998, SendTime: 998, Status: constant.MsgStatusSendSuccess}
			con := &model_struct.LocalConversation{ConversationID: "chat", ConversationType: constant.SingleChatType,
				LatestMsg: utils.StructToJsonString(old), LatestMsgSendTime: 998, UnreadCount: 7, DraftText: "keep draft", IsPinned: true, MaxSeq: 1000}
			want := int64(1000)
			switch mode {
			case "pending", "failed":
				old.Seq, old.ClientMsgID, old.Status = 0, "pending", constant.MsgStatusSending
				if mode == "failed" {
					old.Status = constant.MsgStatusSendFailed
				}
				con.LatestMsg = utils.StructToJsonString(old)
				want = 0
			case "hidden":
				con.LatestMsgSendTime = 0
				want = 998
			case "cleared":
				con.LatestMsg = ""
				want = 0
			case "private":
				con.IsPrivateChat = true
				want = 998
			case "visibility":
				con.MinSeq = 1001
				want = 998
			}
			before := *con
			if err := d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{con}); err != nil {
				t.Fatal(err)
			}
			message := &model_struct.LocalChatLog{ClientMsgID: "m1000", Seq: 1000, SendTime: 1000, SendID: "peer", RecvID: "self",
				SessionType: constant.SingleChatType, ContentType: constant.Text, Content: `{"content":"new"}`, Status: constant.MsgStatusSendSuccess}
			switch mode {
			case "clock reversal":
				message.SendTime = 900
			case "deleted":
				message.Status, want = constant.MsgStatusHasDeleted, 998
			case "filtered":
				message.Status, want = constant.MsgStatusFiltered, 998
			case "revoked":
				if err := d.SaveMessageRevocation(cmd.Ctx, &sdkws.RevokeMsgTips{ConversationID: "chat", Seq: 1000, RevokerUserID: "peer"}); err != nil {
					t.Fatal(err)
				}
			}
			if mode == "history" {
				var list []*model_struct.LocalChatLog
				if err := c.pullMessageIntoTable(cmd.Ctx, "chat", []*model_struct.LocalChatLog{message}, &list); err != nil {
					t.Fatal(err)
				}
				stored, err := d.GetConversation(cmd.Ctx, "chat")
				if err != nil {
					t.Fatal(err)
				}
				var latest sdk_struct.MsgStruct
				if err := json.Unmarshal([]byte(stored.LatestMsg), &latest); err != nil || latest.Seq != 1000 {
					t.Fatalf("history left stale preview: %+v %v", latest, err)
				}
			} else if err := d.BatchInsertMessageList(cmd.Ctx, "chat", []*model_struct.LocalChatLog{message}); err != nil {
				t.Fatal(err)
			}
			for i := 0; i < 2; i++ {
				rows, err := c.GetMultipleConversation(cmd.Ctx, []string{"chat"})
				if err != nil || len(rows) != 1 {
					t.Fatalf("rows=%v error=%v", rows, err)
				}
				var latest sdk_struct.MsgStruct
				if rows[0].LatestMsg != "" {
					if err := json.Unmarshal([]byte(rows[0].LatestMsg), &latest); err != nil {
						t.Fatal(err)
					}
				}
				if latest.Seq != want {
					t.Fatalf("preview=%d want=%d", latest.Seq, want)
				}
				if mode == "revoked" && latest.ContentType != constant.RevokeNotification {
					t.Fatal("recalled body resurrected")
				}
				if rows[0].UnreadCount != before.UnreadCount || rows[0].DraftText != before.DraftText || rows[0].IsPinned != before.IsPinned || rows[0].MinSeq != before.MinSeq || rows[0].MaxSeq != before.MaxSeq || callbacks.received != 0 {
					t.Fatalf("preview repair changed unrelated state: %+v", rows[0])
				}
				if want != 1000 && rows[0].LatestMsg != before.LatestMsg {
					t.Fatal("intentional preview overwritten")
				}
			}
		})
	}
}

func TestConfirmedPreviewOrderIgnoresClockReversal(t *testing.T) {
	row := func(seq, time int64) *model_struct.LocalConversation {
		return &model_struct.LocalConversation{LatestMsgSendTime: time, LatestMsg: utils.StructToJsonString(&sdk_struct.MsgStruct{Seq: seq, SendTime: time})}
	}
	if !newerConversationPreview(row(1000, 900), row(998, 998)) ||
		newerConversationPreview(row(998, 1100), row(1000, 1000)) {
		t.Fatal("preview order differs from confirmed timeline order")
	}
}

func TestPreviewRepairRacesDeleteSQLite(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	c.msgListener = func() open_im_sdk_callback.OnAdvancedMsgListener { return &previewDeleteListener{} }
	d, err := db.NewDataBase(cmd.Ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(context.Background()) })
	c.db = d
	old := &sdk_struct.MsgStruct{ClientMsgID: "old", Seq: 998, SendTime: 998}
	if err := d.BatchInsertConversationList(cmd.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", LatestMsg: utils.StructToJsonString(old), LatestMsgSendTime: 998, UnreadCount: 7}}); err != nil {
		t.Fatal(err)
	}
	if err := d.BatchInsertMessageList(cmd.Ctx, "chat", []*model_struct.LocalChatLog{
		{ClientMsgID: "old", Seq: 998, SendTime: 998, Status: 2, IsRead: true, ContentType: constant.Text, Content: `{"content":"old"}`},
		{ClientMsgID: "new", Seq: 1000, SendTime: 1000, Status: 2, IsRead: true, ContentType: constant.Text, Content: `{"content":"new"}`},
	}); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errors := make(chan error, 2)
	wg.Add(2)
	go func() { defer wg.Done(); _, err := c.GetMultipleConversation(cmd.Ctx, []string{"chat"}); errors <- err }()
	go func() { defer wg.Done(); errors <- c.deleteMessageFromLocal(cmd.Ctx, "chat", "new") }()
	wg.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	rows, err := c.GetMultipleConversation(cmd.Ctx, []string{"chat"})
	if err != nil {
		t.Fatal(err)
	}
	var latest sdk_struct.MsgStruct
	if err := json.Unmarshal([]byte(rows[0].LatestMsg), &latest); err != nil {
		t.Fatal(err)
	}
	if latest.Seq != 998 || rows[0].UnreadCount != 7 {
		t.Fatalf("delete lost: %+v %+v", latest, rows[0])
	}
}

type previewDeleteListener struct {
	open_im_sdk_callback.OnAdvancedMsgListener
}

func (*previewDeleteListener) OnMsgDeleted(string) {}
