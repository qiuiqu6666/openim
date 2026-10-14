package conversation_msg

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
	"google.golang.org/protobuf/proto"
)

// Unlike the original recovery fake, retain all rows and model conflict-ignore
// inserts: a retry must observe messages committed by the preceding attempt.
type messageLossDB struct {
	*transactionalRecoveryDB
	rows       map[string]*model_struct.LocalChatLog
	previewErr error
}

func (d *messageLossDB) GetMessagesByClientMsgIDs(_ context.Context, _ string, ids []string) ([]*model_struct.LocalChatLog, error) {
	var rows []*model_struct.LocalChatLog
	for _, id := range ids {
		if row := d.rows[id]; row != nil {
			copy := *row
			rows = append(rows, &copy)
		}
	}
	return rows, nil
}

func (d *messageLossDB) BatchInsertMessageMap(_ context.Context, rows map[string][]*model_struct.LocalChatLog) error {
	if d.writeErr != nil {
		return d.writeErr
	}
	for _, messages := range rows {
		for _, row := range messages {
			if d.rows[row.ClientMsgID] == nil {
				copy := *row
				d.rows[row.ClientMsgID] = &copy
			}
		}
	}
	return nil
}

func (d *messageLossDB) UpdateMessage(_ context.Context, _ string, row *model_struct.LocalChatLog) error {
	if d.updateErr != nil {
		return d.updateErr
	}
	stored := d.rows[row.ClientMsgID]
	if stored == nil {
		return errors.New("missing message")
	}
	stored.Seq, stored.Status, stored.SendTime, stored.ServerMsgID = row.Seq, row.Status, row.SendTime, row.ServerMsgID
	return nil
}

func (d *messageLossDB) UpdateColumnsConversation(_ context.Context, _ string, fields map[string]interface{}) error {
	if d.previewErr != nil {
		return d.previewErr
	}
	if value, ok := fields["latest_msg"].(string); ok {
		d.conversation.LatestMsg = value
	}
	return nil
}

func selfMessageLossFixture(t *testing.T) (*Conversation, *messageLossDB, *recoveryCallbacks, common.Cmd2Value) {
	t.Helper()
	c, base, callbacks, cmd := recoveryConversation(t)
	db := &messageLossDB{transactionalRecoveryDB: &transactionalRecoveryDB{base}, rows: map[string]*model_struct.LocalChatLog{}}
	c.db = db
	msg := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs[0]
	msg.SendID, msg.RecvID, msg.Seq, msg.SendTime = "self", "other", 1000, 1000
	base.conversation.LatestMsg = `{"clientMsgID":"old","seq":998,"sendTime":998}`
	base.conversation.LatestMsgSendTime = 998
	base.conversation.UnreadCount = 3
	return c, db, callbacks, cmd
}

func previewSeq(t *testing.T, db *messageLossDB) int64 {
	t.Helper()
	var msg sdk_struct.MsgStruct
	if err := json.Unmarshal([]byte(db.conversation.LatestMsg), &msg); err != nil {
		t.Fatal(err)
	}
	return msg.Seq
}

func TestSelfOtherDeviceRetryRepairsConversationAndDeliversOnce(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	db.conversationErr = errors.New("conversation write failed after message commit")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected partial write failure")
	}
	if db.rows["m6"] == nil || callbacks.received != 0 || previewSeq(t, db) != 998 {
		t.Fatal("invalid partial-write setup")
	}
	db.conversationErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if previewSeq(t, db) != 1000 || callbacks.received != 1 {
		t.Fatalf("retry lost self delivery: preview=%d received=%d", previewSeq(t, db), callbacks.received)
	}
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if db.conversation.UnreadCount != 3 || callbacks.received != 1 || len(db.rows) != 1 {
		t.Fatalf("duplicate self replay: unread=%d callbacks=%d rows=%d", db.conversation.UnreadCount, callbacks.received, len(db.rows))
	}
}

func TestSelfLocalPendingRetryRepairsPreviewWithoutNewDelivery(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	msg := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs[0]
	db.rows[msg.ClientMsgID] = &model_struct.LocalChatLog{ClientMsgID: msg.ClientMsgID, Seq: 0, SendID: "self", Status: constant.MsgStatusSending, SendTime: 1001}
	db.conversation.LatestMsg = utils.StructToJsonString(&sdk_struct.MsgStruct{ClientMsgID: msg.ClientMsgID, Seq: 0, SendTime: 1001})
	db.conversation.LatestMsgSendTime = 1001
	db.previewErr = errors.New("preview write failed after self ack")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected preview failure")
	}
	if db.rows[msg.ClientMsgID].Seq != 1000 || previewSeq(t, db) != 0 {
		t.Fatal("invalid self-ack partial-write setup")
	}
	db.previewErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if previewSeq(t, db) != 1000 || callbacks.received != 0 || len(db.rows) != 1 {
		t.Fatalf("self ack not repaired idempotently: preview=%d callbacks=%d rows=%d", previewSeq(t, db), callbacks.received, len(db.rows))
	}
}

func TestSelfOtherDeviceRetryAfterUnreadFailureKeepsDelivery(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	batch := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"]
	peer := proto.Clone(batch.Msgs[0]).(*sdkws.MsgData)
	peer.SendID, peer.RecvID, peer.ClientMsgID, peer.Seq, peer.SendTime = "other", "self", "peer999", 999, 999
	batch.Msgs = append([]*sdkws.MsgData{peer}, batch.Msgs...)
	db.unreadErr = errors.New("unread total failed after all writes")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected unread failure")
	}
	if previewSeq(t, db) != 1000 || callbacks.received != 0 {
		t.Fatal("invalid post-commit failure setup")
	}
	db.unreadErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 2 || db.conversation.UnreadCount != 4 || len(db.rows) != 2 {
		t.Fatalf("retry omitted self or duplicated unread: callbacks=%d unread=%d rows=%d", callbacks.received, db.conversation.UnreadCount, len(db.rows))
	}
}

func TestSelfPersistedDeletedMessageIsNotResurrected(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	db.rows["m6"] = &model_struct.LocalChatLog{ClientMsgID: "m6", Seq: 1000, SendID: "self", Status: constant.MsgStatusHasDeleted}
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if previewSeq(t, db) != 998 || callbacks.received != 0 || db.rows["m6"].Status != constant.MsgStatusHasDeleted {
		t.Fatal("self replay restored a deleted message")
	}
}

func TestSelfNormalAndRepeatedDeliveryIsIdempotent(t *testing.T) {
	for _, duplicateBatch := range []bool{false, true} {
		c, db, callbacks, cmd := selfMessageLossFixture(t)
		batch := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"]
		if duplicateBatch {
			batch.Msgs = append(batch.Msgs, batch.Msgs[0])
		}
		for attempt := 0; attempt < 3; attempt++ {
			if err := c.doMsgNew(cmd); err != nil {
				t.Fatal(err)
			}
		}
		if callbacks.received != 1 || len(db.rows) != 1 || db.conversation.UnreadCount != 3 || len(c.pendingSelfDeliveries) != 0 {
			t.Fatalf("duplicate batch=%v: callbacks=%d rows=%d unread=%d pending=%d", duplicateBatch, callbacks.received, len(db.rows), db.conversation.UnreadCount, len(c.pendingSelfDeliveries))
		}
	}
}

func TestSelfLocalPendingSuccessDoesNotEmitRemoteDelivery(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	db.rows["m6"] = &model_struct.LocalChatLog{ClientMsgID: "m6", SendID: "self", Status: constant.MsgStatusSending}
	db.conversation.LatestMsg = `{"clientMsgID":"m6","seq":0,"sendTime":1000}`
	db.conversation.LatestMsgSendTime = 1000
	for attempt := 0; attempt < 2; attempt++ {
		if err := c.doMsgNew(cmd); err != nil {
			t.Fatal(err)
		}
	}
	if previewSeq(t, db) != 1000 || callbacks.received != 0 || len(db.rows) != 1 || db.conversation.UnreadCount != 3 {
		t.Fatal("local acknowledgement became a duplicate new message")
	}
}

func TestSelfAlreadyPersistedReplayDoesNotUnhideOrUnclearConversation(t *testing.T) {
	for _, hidden := range []bool{false, true} {
		c, db, callbacks, cmd := selfMessageLossFixture(t)
		db.rows["m6"] = &model_struct.LocalChatLog{ClientMsgID: "m6", SendID: "self", Seq: 1000, Status: constant.MsgStatusSendSuccess}
		db.conversation.LatestMsg = ""
		if hidden {
			db.conversation.LatestMsgSendTime = 0
		}
		if err := c.doMsgNew(cmd); err != nil {
			t.Fatal(err)
		}
		if db.conversation.LatestMsg != "" || callbacks.received != 0 || len(db.rows) != 1 {
			t.Fatal("duplicate self message restored a hidden/cleared conversation")
		}
	}
}

func TestSelfCancelledSessionCannotReplayPendingDelivery(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	db.conversationErr = errors.New("partial commit")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected partial write")
	}
	db.conversationErr = nil
	ctx, cancel := context.WithCancel(cmd.Ctx)
	cancel()
	cmd.Ctx, cmd.Receipt = ctx, make(chan error, 1)
	c.Work(cmd)
	if err := <-cmd.Receipt; !errors.Is(err, context.Canceled) {
		t.Fatalf("expired account accepted replay: %v", err)
	}
	if callbacks.received != 0 || previewSeq(t, db) != 998 {
		t.Fatal("expired account delivered pending self message")
	}
}

// Expose the ordinary DB interface, not BatchInsertMessageMap, to exercise
// the production fallback that may commit a prefix before returning an error.
type partialMessageLossDB struct {
	db_interface.DataBase
	rows *messageLossDB
	fail bool
}

func (d *partialMessageLossDB) BatchInsertMessageList(ctx context.Context, id string, rows []*model_struct.LocalChatLog) error {
	if d.fail {
		copy := *rows[0]
		d.rows.rows[copy.ClientMsgID] = &copy
		return errors.New("partial batch failure")
	}
	return d.rows.BatchInsertMessageMap(ctx, map[string][]*model_struct.LocalChatLog{id: rows})
}

func (d *partialMessageLossDB) InsertMessage(_ context.Context, _ string, row *model_struct.LocalChatLog) error {
	return errors.New("fallback insert failure")
}

func (d *partialMessageLossDB) GetMessage(_ context.Context, _ string, id string) (*model_struct.LocalChatLog, error) {
	if row := d.rows.rows[id]; row != nil {
		return row, nil
	}
	return nil, errs.ErrRecordNotFound
}

func TestSelfOtherDevicePartialMessageBatchRetainsDelivery(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	fallback := &partialMessageLossDB{DataBase: db, rows: db, fail: true}
	c.db = fallback
	batch := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"]
	peer := proto.Clone(batch.Msgs[0]).(*sdkws.MsgData)
	peer.SendID, peer.RecvID, peer.ClientMsgID, peer.Seq, peer.SendTime = "other", "self", "peer1001", 1001, 1001
	batch.Msgs = append(batch.Msgs, peer)
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected partially committed message batch")
	}
	if db.rows["m6"] == nil || db.rows["peer1001"] != nil || callbacks.received != 0 {
		t.Fatal("invalid partial message batch setup")
	}
	fallback.fail = false
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 2 || db.conversation.UnreadCount != 4 || len(db.rows) != 2 {
		t.Fatalf("self delivery lost after partial message insertion: callbacks=%d unread=%d rows=%d", callbacks.received, db.conversation.UnreadCount, len(db.rows))
	}
}

func TestSelfNewDeliveryToHiddenConversationStillRecoversAfterFailure(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	db.conversation.LatestMsg, db.conversation.LatestMsgSendTime = "", 0
	db.conversationErr = errors.New("hidden conversation write failed")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected hidden row write failure")
	}
	db.conversationErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if previewSeq(t, db) != 1000 || db.conversation.LatestMsgSendTime != 1000 || callbacks.received != 1 {
		t.Fatal("pending new self delivery failed to restore its conversation")
	}
}

func TestSelfRetryUsesSamePreviewOrderingAsInitialDelivery(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	db.conversation.LatestMsg, db.conversation.LatestMsgSendTime = `{"clientMsgID":"old","seq":998,"sendTime":150}`, 150
	batch := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"]
	batch.Msgs[0].Seq, batch.Msgs[0].SendTime = 999, 200
	later := proto.Clone(batch.Msgs[0]).(*sdkws.MsgData)
	later.ClientMsgID, later.Seq, later.SendTime = "m1000", 1000, 100
	batch.Msgs = append(batch.Msgs, later)
	db.conversationErr = errors.New("preview ordering retry")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected partial write")
	}
	db.conversationErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if previewSeq(t, db) != 999 || callbacks.received != 2 {
		t.Fatalf("retry changed preview ordering: seq=%d callbacks=%d", previewSeq(t, db), callbacks.received)
	}
}

func TestSelfHiddenPendingPreviewIgnoresOldDeliveredCandidate(t *testing.T) {
	c, db, callbacks, cmd := selfMessageLossFixture(t)
	db.conversation.LatestMsg, db.conversation.LatestMsgSendTime = "", 0
	batch := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"]
	batch.Msgs[0].Seq, batch.Msgs[0].SendTime = 1001, 100
	old := proto.Clone(batch.Msgs[0]).(*sdkws.MsgData)
	old.ClientMsgID, old.Seq, old.SendTime = "old1000", 1000, 200
	db.rows[old.ClientMsgID] = &model_struct.LocalChatLog{ClientMsgID: old.ClientMsgID, Seq: old.Seq,
		SendID: "self", SendTime: old.SendTime, Status: constant.MsgStatusSendSuccess}
	batch.Msgs = append(batch.Msgs, old)
	db.conversationErr = errors.New("hidden mixed candidate write failed")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected hidden row write failure")
	}
	db.conversationErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if db.conversation.LatestMsg == "" || previewSeq(t, db) != 1001 || db.conversation.LatestMsgSendTime != 100 || callbacks.received != 1 {
		t.Fatalf("old delivered candidate hid pending preview: latest=%s time=%d callbacks=%d",
			db.conversation.LatestMsg, db.conversation.LatestMsgSendTime, callbacks.received)
	}
}
