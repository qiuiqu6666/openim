//go:build cgo && !js

package conversation_msg

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type initialPreviewCallbacks struct {
	*recoveryCallbacks
	progress []int
	changed  int
}

func (l *initialPreviewCallbacks) OnSyncServerProgress(n int) { l.progress = append(l.progress, n) }

func (l *initialPreviewCallbacks) OnConversationChanged(string) { l.changed++ }

func TestInitialBackfillPreservesLatestPreviewSQLite(t *testing.T) {
	for _, live := range []bool{false, true} {
		t.Run(fmt.Sprint("live=", live), func(t *testing.T) {
			c, _, callbacks, base := recoveryConversation(t)
			d, err := db.NewDataBase(base.Ctx, "self", t.TempDir(), 0)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = d.Close(context.Background()) })
			c.db = d
			listener := &initialPreviewCallbacks{recoveryCallbacks: callbacks}
			c.ConversationListener = func() open_im_sdk_callback.OnConversationListener { return listener }
			if err := d.InsertLoginUser(base.Ctx, &model_struct.LocalUser{UserID: "self"}); err != nil {
				t.Fatal(err)
			}
			if err := d.BatchInsertConversationList(base.Ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsg: "{}", UnreadCount: 100}}); err != nil {
				t.Fatal(err)
			}
			store := func(seq int64) {
				t.Helper()
				packet := &sdkws.PullMsgs{Msgs: []*sdkws.MsgData{{ClientMsgID: fmt.Sprintf("m%d", seq), SendID: "self", RecvID: "other", Seq: seq, SendTime: 100, SessionType: constant.SingleChatType, ContentType: constant.Text, Content: []byte(`{"content":"hello"}`), Status: constant.MsgStatusSendSuccess}}}
				cmd := common.Cmd2Value{Ctx: base.Ctx, Cmd: constant.CmdMsgSyncInReinstall, Value: sdk_struct.CmdMsgSyncInReinstall{Msgs: map[string]*sdkws.PullMsgs{"chat": packet}, Total: 2, NotifyConversations: seq >= 1000}}
				if err := c.doMsgSyncByReinstalled(cmd); err != nil {
					t.Fatal(err)
				}
			}
			store(1000)
			if listener.changed != 1 {
				t.Fatal("latest preview was not published before backfill")
			}
			if rows, err := d.GetConversationListSplitDB(base.Ctx, 0, 100); err != nil || len(rows) != 1 {
				t.Fatalf("preview not visible: %v %v", rows, err)
			}
			want := int64(1000)
			if live {
				store(1001)
				want = 1001
			}
			store(999)
			wantNotifications := 1
			if live {
				wantNotifications++
			}
			if listener.changed != wantNotifications {
				t.Fatal("background history published a stale preview")
			}
			row, err := d.GetConversation(base.Ctx, "chat")
			if err != nil {
				t.Fatal(err)
			}
			var latest sdk_struct.MsgStruct
			if err := json.Unmarshal([]byte(row.LatestMsg), &latest); err != nil {
				t.Fatal(err)
			}
			if latest.Seq != want || row.LatestMsgSendTime != 100 || row.UnreadCount != 100 {
				t.Fatalf("backfill changed preview/unread: %+v", row)
			}
			if _, err := d.GetMessageBySeq(base.Ctx, "chat", 999); err != nil {
				t.Fatal("history row was not stored", err)
			}
			for _, n := range listener.progress {
				if n >= 100 {
					t.Fatal("reported completion before terminal sync flag")
				}
			}
		})
	}
}
