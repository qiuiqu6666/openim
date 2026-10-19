//go:build cgo && !js

package conversation_msg

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/internal/user"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

// Reproduce the logged cold group receipt, then exercise the existing profile
// sync that becomes reachable after the notification page can finish.
func TestHeatRecoveryColdReceiptThenProfileSyncSQLite(t *testing.T) {
	var requests atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		_, _ = w.Write([]byte(`{"errCode":0,"data":{"usersInfo":[{"userID":"self","nickname":"restored","faceURL":"restored face"}]}}`))
	}))
	defer srv.Close()
	ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "heat-recovery"), &ccontext.GlobalConfig{UserID: "self", IMConfig: sdk_struct.IMConfig{ApiAddr: srv.URL}})
	store, err := db.NewDataBase(ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close(context.Background()) })
	const groupID = "sg_@lg_cold_heat"
	for _, conv := range []*model_struct.LocalConversation{
		{ConversationID: groupID, ConversationType: constant.ReadGroupChatType, UnreadCount: 4},
		{ConversationID: "chat", ConversationType: constant.SingleChatType, UnreadCount: 2},
	} {
		if err := store.InsertConversation(ctx, conv); err != nil {
			t.Fatal(err)
		}
	}
	c, _, _ := watermarkFixture()
	c.db = store
	c.user = user.NewUser(store, "self", c.GetCh())
	tips := &sdkws.MarkAsReadTips{ConversationID: groupID, MarkAsReadUserID: "peer", Seqs: []int64{310412, 310411, 310410, 310409}}
	msg := &sdkws.MsgData{Seq: 1631, ContentType: constant.HasReadReceipt, SendTime: 1234, Content: []byte(utils.StructToJsonString(sdk_struct.NotificationElem{Detail: utils.StructToJsonString(tips)}))}
	cmd := common.Cmd2Value{Ctx: ctx, Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_heat": {Msgs: []*sdkws.MsgData{msg}}}}}
	if err := c.doNotificationManager(cmd); err != nil {
		t.Fatal(err)
	}
	seqs, err := store.GetNotificationAllSeqs(ctx)
	if err != nil || len(seqs) != 1 || seqs[0].Seq != 1631 {
		t.Fatalf("cold receipt did not advance: %v %v", seqs, err)
	}
	if err := c.user.SyncLoginUserInfo(ctx); err != nil {
		t.Fatal(err)
	}
	profile, err := store.GetLoginUser(ctx, "self")
	if err != nil || profile.Nickname != "restored" {
		t.Fatalf("profile not persisted: %+v %v", profile, err)
	}
	for i := 0; i < 100; i++ {
		row := &model_struct.LocalChatLog{SendID: "self", SenderNickname: "wire", Seq: 9, IsRead: true}
		c.faceURLAndNicknameHandle(ctx, []*model_struct.LocalChatLog{row}, nil, "chat")
		if row.SenderNickname != "restored" || !row.IsRead || row.Seq != 9 {
			t.Fatalf("recovered metadata changed message state: %+v", row)
		}
	}
	if requests.Load() != 1 {
		t.Fatalf("message path fetched profile repeatedly: %d", requests.Load())
	}
	conv, err := store.GetConversation(ctx, groupID)
	if err != nil || conv.UnreadCount != 4 {
		t.Fatalf("peer group receipt changed own unread: %+v %v", conv, err)
	}
}

type heatReceiptFailureDB struct {
	*db.DataBase
	fail bool
}

func (d *heatReceiptFailureDB) GetMessagesBySeqs(ctx context.Context, id string, seqs []int64) ([]*model_struct.LocalChatLog, error) {
	if d.fail {
		return nil, errors.New("injected disk read failure")
	}
	return d.DataBase.GetMessagesBySeqs(ctx, id, seqs)
}

func TestHeatRecoveryReceiptFailureKeepsCheckpointAndReadStateSQLite(t *testing.T) {
	ctx := context.Background()
	store, err := db.NewDataBase(ctx, "self", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close(ctx) })
	if err := store.InsertConversation(ctx, &model_struct.LocalConversation{ConversationID: "chat", ConversationType: constant.SingleChatType, UnreadCount: 2}); err != nil {
		t.Fatal(err)
	}
	if err := store.BatchInsertMessageList(ctx, "chat", []*model_struct.LocalChatLog{
		{ClientMsgID: "own", SendID: "self", Seq: 4, SendTime: 4, AttachedInfo: "{}"},
		{ClientMsgID: "later", SendID: "self", Seq: 5, SendTime: 5, AttachedInfo: "{}"},
	}); err != nil {
		t.Fatal(err)
	}
	if err := store.SetNotificationSeq(ctx, "n_chat", 56); err != nil {
		t.Fatal(err)
	}
	wrapper := &heatReceiptFailureDB{DataBase: store, fail: true}
	c, _, listener := watermarkFixture()
	c.db = wrapper
	tips := &sdkws.MarkAsReadTips{ConversationID: "chat", MarkAsReadUserID: "peer", Seqs: []int64{4, 500}}
	msg := &sdkws.MsgData{Seq: 57, ContentType: constant.HasReadReceipt, SendTime: 1234, Content: []byte(utils.StructToJsonString(sdk_struct.NotificationElem{Detail: utils.StructToJsonString(tips)}))}
	cmd := common.Cmd2Value{Ctx: ctx, Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_chat": {Msgs: []*sdkws.MsgData{msg}}}}}
	if err := c.doNotificationManager(cmd); err == nil {
		t.Fatal("storage failure was swallowed")
	}
	seqs, err := store.GetNotificationAllSeqs(ctx)
	if err != nil || len(seqs) != 1 || seqs[0].Seq != 56 || len(listener.receipts) != 0 {
		t.Fatalf("failed page acknowledged: %v %v", seqs, err)
	}
	wrapper.fail = false
	for i := 0; i < 2; i++ {
		if err := c.doNotificationManager(cmd); err != nil {
			t.Fatal(err)
		}
	}
	seqs, err = store.GetNotificationAllSeqs(ctx)
	if err != nil || seqs[0].Seq != 57 {
		t.Fatalf("retry failed to commit: %v %v", seqs, err)
	}
	own, err := store.GetMessageBySeq(ctx, "chat", 4)
	if err != nil || !own.IsRead {
		t.Fatalf("receipt lost: %+v %v", own, err)
	}
	later, err := store.GetMessageBySeq(ctx, "chat", 5)
	if err != nil || later.IsRead {
		t.Fatalf("unrelated message marked read: %+v %v", later, err)
	}
	conv, err := store.GetConversation(ctx, "chat")
	if err != nil || conv.UnreadCount != 2 || conv.LatestMsg != "" {
		t.Fatalf("receipt changed unread/empty preview: %+v %v", conv, err)
	}
	if len(listener.receipts) != 2 {
		t.Fatalf("missing receipt callbacks: %v", listener.receipts)
	}
}
