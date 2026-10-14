package conversation_msg

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/internal/interaction"
	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
)

type recoveryDB struct {
	db_interface.DataBase
	conversation                                    model_struct.LocalConversation
	writeErr, conversationErr, unreadErr, updateErr error
	stored                                          *model_struct.LocalChatLog
}

func (d *recoveryDB) GetConversation(context.Context, string) (*model_struct.LocalConversation, error) {
	c := d.conversation
	return &c, nil
}
func (d *recoveryDB) GetMultipleConversationDB(context.Context, []string) ([]*model_struct.LocalConversation, error) {
	c := d.conversation
	return []*model_struct.LocalConversation{&c}, nil
}
func (d *recoveryDB) GetLoginUser(context.Context, string) (*model_struct.LocalUser, error) {
	return &model_struct.LocalUser{}, nil
}
func (d *recoveryDB) BatchInsertMessageList(_ context.Context, _ string, ms []*model_struct.LocalChatLog) error {
	if d.writeErr != nil {
		return d.writeErr
	}
	if len(ms) > 0 {
		d.stored = ms[0]
	}
	return nil
}
func (d *recoveryDB) InsertMessage(_ context.Context, _ string, m *model_struct.LocalChatLog) error {
	if d.writeErr != nil {
		return d.writeErr
	}
	d.stored = m
	return nil
}
func (d *recoveryDB) GetMessage(context.Context, string, string) (*model_struct.LocalChatLog, error) {
	if d.stored == nil {
		return nil, errs.ErrRecordNotFound
	}
	return d.stored, nil
}
func (d *recoveryDB) BatchUpdateConversationList(_ context.Context, cs []*model_struct.LocalConversation) error {
	if d.conversationErr != nil {
		return d.conversationErr
	}
	for _, c := range cs {
		d.conversation = *c
	}
	return nil
}
func (d *recoveryDB) BatchInsertConversationList(context.Context, []*model_struct.LocalConversation) error {
	return nil
}
func (d *recoveryDB) GetTotalUnreadMsgCountDB(context.Context) (int32, error) {
	return d.conversation.UnreadCount, d.unreadErr
}
func (d *recoveryDB) UpdateMessage(_ context.Context, _ string, m *model_struct.LocalChatLog) error {
	if d.updateErr != nil {
		return d.updateErr
	}
	d.stored = m
	return nil
}

type transactionalRecoveryDB struct{ *recoveryDB }

func (d *transactionalRecoveryDB) BatchInsertMessageMap(ctx context.Context, msgs map[string][]*model_struct.LocalChatLog) error {
	for id, ms := range msgs {
		if err := d.BatchInsertMessageList(ctx, id, ms); err != nil {
			return err
		}
	}
	return nil
}

type recoveryCallbacks struct {
	open_im_sdk_callback.OnConversationListener
	open_im_sdk_callback.OnAdvancedMsgListener
	received int
}

func (c *recoveryCallbacks) OnRecvNewMessage(string)                { c.received++ }
func (c *recoveryCallbacks) OnConversationChanged(string)           {}
func (c *recoveryCallbacks) OnTotalUnreadMessageCountChanged(int32) {}

func recoveryConversation(t *testing.T) (*Conversation, *recoveryDB, *recoveryCallbacks, common.Cmd2Value) {
	t.Helper()
	ctx := ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{UserID: "self"})
	d := &recoveryDB{conversation: model_struct.LocalConversation{ConversationID: "chat", ConversationType: constant.SingleChatType, LatestMsgSendTime: 1}}
	l := &recoveryCallbacks{}
	c := &Conversation{
		LongConnMgr: interaction.NewLongConnMgr(ctx, nil, nil, nil, nil),
		db:          &transactionalRecoveryDB{d}, loginUserID: "self", maxSeqRecorder: NewMaxSeqRecorder(),
		ConversationListener: func() open_im_sdk_callback.OnConversationListener { return l },
		msgListener:          func() open_im_sdk_callback.OnAdvancedMsgListener { return l },
		batchMsgListener:     func() open_im_sdk_callback.OnBatchMsgListener { return nil },
	}
	c.maxSeqRecorder.Set("chat", 5)
	cmd := common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdNewMsgCome, Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{
		"chat": {Msgs: []*sdkws.MsgData{{ClientMsgID: "m6", SendID: "other", RecvID: "self", Seq: 6, SendTime: 6, SessionType: constant.SingleChatType, ContentType: constant.Text, Content: []byte(`{"content":"hello"}`)}}},
	}}}
	return c, d, l, cmd
}

func TestMessageStorageFailureReturnsReceiptAndRetryDelivers(t *testing.T) {
	for _, stage := range []string{"messages", "conversation"} {
		t.Run(stage, func(t *testing.T) {
			c, d, callbacks, cmd := recoveryConversation(t)
			want := errors.New("disk full")
			if stage == "messages" {
				d.writeErr = want
			} else {
				d.conversationErr = want
			}
			cmd.Receipt = make(chan error, 1)
			c.Work(cmd)
			if err := <-cmd.Receipt; !errors.Is(err, want) {
				t.Fatalf("lost write failure: %v", err)
			}
			if callbacks.received != 0 || c.maxSeqRecorder.Get("chat") != 5 {
				t.Fatal("failed storage emitted message or advanced unread sequence")
			}
			d.writeErr, d.conversationErr = nil, nil
			c.Work(cmd)
			if err := <-cmd.Receipt; err != nil {
				t.Fatal(err)
			}
			if callbacks.received != 1 || d.stored == nil || d.stored.Seq != 6 || d.conversation.UnreadCount != 1 || c.maxSeqRecorder.Get("chat") != 6 {
				t.Fatalf("retry did not persist/deliver correctly: received=%d conversation=%+v seq=%d", callbacks.received, d.conversation, c.maxSeqRecorder.Get("chat"))
			}
		})
	}
}

func TestPartialCommitRetryDoesNotDoubleUnread(t *testing.T) {
	c, d, callbacks, cmd := recoveryConversation(t)
	d.unreadErr = errors.New("unread query failed after writes")
	if err := c.doMsgNew(cmd); err == nil {
		t.Fatal("expected unread read failure")
	}
	if callbacks.received != 0 || d.conversation.UnreadCount != 1 {
		t.Fatal("wrong partial commit")
	}
	d.unreadErr = nil
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if callbacks.received != 1 || d.conversation.UnreadCount != 1 {
		t.Fatalf("retry duplicated unread count: %d", d.conversation.UnreadCount)
	}
}

func TestUnreadUsesActualSequenceAndDeduplicatesBatch(t *testing.T) {
	c, d, _, cmd := recoveryConversation(t)
	p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"]
	p.Msgs[0].Seq = 10
	p.Msgs = append(p.Msgs, p.Msgs[0])
	if err := c.doMsgNew(cmd); err != nil {
		t.Fatal(err)
	}
	if d.conversation.UnreadCount != 1 || c.maxSeqRecorder.Get("chat") != 10 {
		t.Fatalf("duplicate or gap miscount: unread=%d seq=%d", d.conversation.UnreadCount, c.maxSeqRecorder.Get("chat"))
	}
}

func TestFallbackInsertOnlyAcceptsMatchingPersistedSequence(t *testing.T) {
	want := errors.New("insert failed")
	for _, seq := range []int64{0, 5, 6} {
		t.Run(string(rune('0'+seq)), func(t *testing.T) {
			d := &recoveryDB{writeErr: want}
			if seq > 0 {
				d.stored = &model_struct.LocalChatLog{ClientMsgID: "m6", Seq: seq}
			}
			c := &Conversation{db: d}
			err := c.batchInsertMessageList(context.Background(), map[string][]*model_struct.LocalChatLog{"chat": {{ClientMsgID: "m6", Seq: 6}}})
			if seq == 6 && err != nil {
				t.Fatal(err)
			}
			if seq != 6 && !errors.Is(err, want) {
				t.Fatalf("accepted missing/stale row: %v", err)
			}
		})
	}
}

func TestCorruptPreviewStillUpdatesSelfMessageAndReturnsDBFailure(t *testing.T) {
	d := &recoveryDB{conversation: model_struct.LocalConversation{LatestMsg: "not json"}}
	c := &Conversation{db: d}
	updates := map[string][]*model_struct.LocalChatLog{"chat": {{ClientMsgID: "self", Seq: 9, Status: constant.MsgStatusSendSuccess}}}
	if err := c.batchUpdateMessageList(context.Background(), updates); err != nil {
		t.Fatal(err)
	}
	if d.stored == nil || d.stored.Seq != 9 {
		t.Fatal("corrupt preview prevented message update")
	}
	d.updateErr = errors.New("disk full")
	if err := c.batchUpdateMessageList(context.Background(), updates); err == nil {
		t.Fatal("swallowed update failure")
	}
}

func TestMalformedMessageAndExpiredCommandAreNotAcknowledgedAsSuccess(t *testing.T) {
	c, _, callbacks, cmd := recoveryConversation(t)
	cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs[0].Content = []byte("invalid json")
	cmd.Receipt = make(chan error, 1)
	c.Work(cmd)
	if err := <-cmd.Receipt; err == nil {
		t.Fatal("malformed message acknowledged")
	}
	cmd.ExpiresAt = time.Now().Add(-time.Second)
	cmd.Value = nil // Would panic if an expired queued command is executed.
	c.Work(cmd)
	if err := <-cmd.Receipt; !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expiry error: %v", err)
	}
	if callbacks.received != 0 {
		t.Fatal("invalid command emitted message")
	}
}

func TestConversationPanicAcknowledgesFailureAndWorkerContinues(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	c.conversationEventQueue = make(chan common.Cmd2Value, 2)
	bad := common.Cmd2Value{Ctx: cmd.Ctx, Cmd: constant.CmdNewMsgCome, Receipt: make(chan error, 1)}
	cmd.ExpiresAt = time.Now().Add(-time.Second)
	cmd.Receipt = make(chan error, 1)
	c.conversationEventQueue <- bad
	c.conversationEventQueue <- cmd
	close(c.conversationEventQueue)
	done := make(chan struct{})
	go func() { common.DoListener(context.Background(), c); close(done) }()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("worker stuck")
	}
	if err := <-bad.Receipt; err == nil {
		t.Fatal("panic acknowledged as success")
	}
	if err := <-cmd.Receipt; !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("next command was not processed")
	}
}

func TestHugeHistoryGapRemainsBoundedAtIntegerLimits(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		seqs := getLostSeqListWithLimitLength(1, math.MaxInt64, nil, reverse)
		if len(seqs) != constant.PullMsgNumForReadDiffusion {
			t.Fatalf("unbounded gap: %d", len(seqs))
		}
		for i := 1; i < len(seqs); i++ {
			if seqs[i] != seqs[i-1]+1 {
				t.Fatal("sequences not ascending")
			}
		}
		if reverse && seqs[0] != 1 {
			t.Fatal("wrong head")
		}
		if !reverse && seqs[len(seqs)-1] != math.MaxInt64 {
			t.Fatal("wrong tail")
		}
	}
}

func TestRequiredMetadataFailurePropagates(t *testing.T) {
	want := errors.New("metadata unavailable")
	for _, parallel := range []bool{false, true} {
		err := runRequiredSyncFunctions(context.Background(), []func(context.Context) error{func(context.Context) error { return nil }, func(context.Context) error { return want }}, parallel)
		if !errors.Is(err, want) {
			t.Fatalf("metadata error lost: %v", err)
		}
	}
}

func TestMetadataPanicIsReportedInSequentialAndParallelSync(t *testing.T) {
	for _, parallel := range []bool{false, true} {
		err := runRequiredSyncFunctions(context.Background(), []func(context.Context) error{func(context.Context) error { panic("malformed metadata") }}, parallel)
		if err == nil {
			t.Fatal("metadata panic was not reported")
		}
	}
}

func TestRequiredSyncUsesReceiptDeadlineWithoutCancellingFollowups(t *testing.T) {
	parent := context.Background()
	ctx, cancel := syncCommandContext(common.Cmd2Value{Ctx: parent, ExpiresAt: time.Now().Add(20 * time.Millisecond)})
	defer cancel()
	err := runRequiredSyncFunctions(ctx, []func(context.Context) error{func(ctx context.Context) error { <-ctx.Done(); return ctx.Err() }}, true)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("required sync ignored deadline: %v", err)
	}
	if parent.Err() != nil {
		t.Fatal("cancelled background followups")
	}
}

func TestUnreadSyncDoesNotEnqueueToItsOwnFullWorker(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	c.conversationEventQueue = make(chan common.Cmd2Value, 1)
	c.conversationEventQueue <- common.Cmd2Value{}
	ctx, cancel := context.WithTimeout(cmd.Ctx, time.Second)
	defer cancel()
	if err := c.notifySyncedConversations(ctx, []string{"chat"}); err != nil {
		t.Fatal(err)
	}
	if len(c.conversationEventQueue) != 1 {
		t.Fatal("sync modified its own pending queue")
	}
}
