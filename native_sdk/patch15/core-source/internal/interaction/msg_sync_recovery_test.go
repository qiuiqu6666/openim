package interaction

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
	"google.golang.org/protobuf/proto"
)

func recoveryContext(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{UserID: "self"}), 5*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func recoveryMsgs(id string, seqs ...int64) map[string]*sdkws.PullMsgs {
	p := &sdkws.PullMsgs{}
	for _, seq := range seqs {
		p.Msgs = append(p.Msgs, &sdkws.MsgData{Seq: seq})
	}
	return map[string]*sdkws.PullMsgs{id: p}
}

func receiptWorker(t *testing.T, ch <-chan common.Cmd2Value, handle func(common.Cmd2Value) error) {
	t.Helper()
	stop, done := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(done)
		for {
			select {
			case cmd := <-ch:
				err := handle(cmd)
				if cmd.Receipt != nil {
					cmd.Receipt <- err
				}
			case <-stop:
				return
			}
		}
	}()
	t.Cleanup(func() { close(stop); <-done })
}

func requestWorker(t *testing.T, c *LongConnMgr, handle func(Message) *GeneralWsResp) {
	t.Helper()
	stop, done := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(done)
		for {
			select {
			case req := <-c.send:
				req.Resp <- handle(req)
			case <-stop:
				return
			}
		}
	}()
	t.Cleanup(func() { close(stop); <-done })
}

func wireResponse(p proto.Message) *GeneralWsResp {
	data, err := proto.Marshal(p)
	if err != nil {
		panic(err)
	}
	return &GeneralWsResp{Data: data}
}

func TestPullCommitWaitsForStorageAndRetriesFailure(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 5}}
	resp := &sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", 6)}
	ranges := map[string][2]int64{"chat": {6, 6}}
	done := make(chan error, 1)
	go func() { done <- m.commitPulledMessages(ctx, resp, ranges, 0) }()
	cmd := <-m.conversationCh
	if m.syncedMaxSeqs["chat"] != 5 {
		t.Fatal("advanced before storage acknowledgement")
	}
	want := errors.New("disk full")
	cmd.Receipt <- want
	if err := <-done; !errors.Is(err, want) {
		t.Fatalf("lost storage error: %v", err)
	}
	if m.syncedMaxSeqs["chat"] != 5 {
		t.Fatal("advanced after failed storage")
	}
	go func() { done <- m.commitPulledMessages(ctx, resp, ranges, 0) }()
	cmd = <-m.conversationCh
	cmd.Receipt <- nil
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["chat"] != 6 {
		t.Fatal("retry did not commit")
	}
}

func TestNotificationFailureDoesNotCommitItsSequence(t *testing.T) {
	m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 5, "n_chat": 2}}
	want := errors.New("notification write failed")
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd == constant.CmdNotification {
			return want
		}
		return nil
	})
	err := m.commitPulledMessages(recoveryContext(t), &sdkws.PullMessageBySeqsResp{
		Msgs: recoveryMsgs("chat", 6), NotificationMsgs: recoveryMsgs("n_chat", 3),
	}, map[string][2]int64{"chat": {6, 6}, "n_chat": {3, 3}}, 0)
	if !errors.Is(err, want) || m.syncedMaxSeqs["chat"] != 6 || m.syncedMaxSeqs["n_chat"] != 2 {
		t.Fatalf("err=%v positions=%v", err, m.syncedMaxSeqs)
	}
}

func TestWakeupPullFailureThenReconnectRecovers(t *testing.T) {
	ctx := recoveryContext(t)
	c := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, loginUserID: "self", longConnMgr: c, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 5}}
	flags := make(chan int, 8)
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd == constant.CmdSyncFlag {
			flags <- cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).SyncFlag
		}
		return nil
	})
	pulls := 0
	requestWorker(t, c, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.GetNewestSeq {
			return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 6}})
		}
		pulls++
		if pulls == 1 {
			return &GeneralWsResp{ErrCode: 10001, ErrMsg: "offline"}
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", 6)})
	})
	m.startSync()
	m.doWakeupDataSync(ctx)
	if m.isSyncing || m.syncedMaxSeqs["chat"] != 5 {
		t.Fatal("failure left syncing stuck or advanced sequence")
	}
	if got := []int{<-flags, <-flags}; !reflect.DeepEqual(got, []int{constant.MsgSyncBegin, constant.MsgSyncFailed}) {
		t.Fatalf("failure flags: %v", got)
	}
	if !m.startSync() {
		t.Fatal("reconnect could not retry")
	}
	m.doConnected(ctx)
	if m.isSyncing || m.syncedMaxSeqs["chat"] != 6 {
		t.Fatal("reconnect failed to recover")
	}
	if got := []int{<-flags, <-flags}; !reflect.DeepEqual(got, []int{constant.MsgSyncBegin, constant.MsgSyncEnd}) {
		t.Fatalf("success flags: %v", got)
	}
}

type recoveryVersionDB struct {
	db_interface.DataBase
	installed       bool
	writeErr        error
	notificationErr error
	versionWrites   int
	journal         map[string]*model_struct.LocalVersionSync
}

func (d *recoveryVersionDB) GetAllConversationIDList(context.Context) ([]string, error) {
	return []string{"chat"}, nil
}
func (d *recoveryVersionDB) GetAppSDKVersion(context.Context) (*model_struct.LocalAppSDKVersion, error) {
	return &model_struct.LocalAppSDKVersion{Installed: d.installed}, nil
}
func (d *recoveryVersionDB) SetAppSDKVersion(_ context.Context, v *model_struct.LocalAppSDKVersion) error {
	d.versionWrites++
	if d.writeErr != nil {
		return d.writeErr
	}
	d.installed = v.Installed
	return nil
}
func (d *recoveryVersionDB) CheckConversationNormalMsgSeq(context.Context, string) (int64, error) {
	return 0, nil
}
func (d *recoveryVersionDB) GetVersionSync(_ context.Context, table, id string) (*model_struct.LocalVersionSync, error) {
	if row := d.journal[table+id]; row != nil {
		return row, nil
	}
	return nil, errs.ErrRecordNotFound
}
func (d *recoveryVersionDB) SetVersionSync(_ context.Context, row *model_struct.LocalVersionSync) error {
	if d.journal == nil {
		d.journal = make(map[string]*model_struct.LocalVersionSync)
	}
	copy := *row
	copy.UIDList = append([]string(nil), row.UIDList...)
	d.journal[row.Table+row.EntityID] = &copy
	return nil
}
func (d *recoveryVersionDB) GetConversation(context.Context, string) (*model_struct.LocalConversation, error) {
	return &model_struct.LocalConversation{}, nil
}
func (d *recoveryVersionDB) GetNotificationAllSeqs(context.Context) ([]*model_struct.NotificationSeqs, error) {
	return nil, nil
}
func (d *recoveryVersionDB) BatchInsertNotificationSeq(context.Context, []*model_struct.NotificationSeqs) error {
	return d.notificationErr
}

func TestIncompleteInstallSurvivesRestartAndCommitFailure(t *testing.T) {
	ctx := recoveryContext(t)
	d := &recoveryVersionDB{writeErr: errors.New("disk full")}
	m, err := NewMsgSyncer(ctx, make(chan common.Cmd2Value), nil, "self", nil, d, 0)
	if err != nil {
		t.Fatal(err)
	}
	if !m.reinstalled {
		t.Fatal("partial install with existing conversations was marked complete")
	}
	if err := m.compareSeqsAndBatchSync(ctx, nil, 1); err == nil || !m.reinstalled || d.installed {
		t.Fatal("failed Installed write was treated as success")
	}
	d.writeErr = nil
	if err := m.compareSeqsAndBatchSync(ctx, nil, 1); err != nil || m.reinstalled || !d.installed {
		t.Fatalf("install retry failed: %v", err)
	}
}

func TestInstallNotificationStorageFailureStopsCompletion(t *testing.T) {
	d := &recoveryVersionDB{notificationErr: errors.New("disk full")}
	m := &MsgSyncer{db: d, reinstalled: true, syncedMaxSeqs: map[string]int64{}}
	if err := m.compareSeqsAndBatchSync(recoveryContext(t), map[string]int64{"n_self": 20}, 1); err == nil {
		t.Fatal("ignored notification storage error")
	}
	if d.versionWrites != 0 || !m.reinstalled || m.syncedMaxSeqs["n_self"] != 0 {
		t.Fatal("committed incomplete initial sync")
	}
}

func TestPushStorageFailureKeepsGapRecoverable(t *testing.T) {
	m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value, 2), syncedMaxSeqs: map[string]int64{"chat": 5}}
	m.pushTriggerAndSync(recoveryContext(t), recoveryMsgs("chat", 6), func(context.Context, map[string]*sdkws.PullMsgs) error { return errors.New("disk full") })
	if m.syncedMaxSeqs["chat"] != 5 {
		t.Fatal("failed push skipped its sequence")
	}
	cmd := <-m.conversationCh
	if cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).SyncFlag != constant.MsgSyncFailed {
		t.Fatal("missing recovery failure event")
	}
}

func TestDuplicateOrOutOfOrderPushPullsOnlyUncoveredGap(t *testing.T) {
	for _, seqs := range [][]int64{{7, 7}, {7, 6}} {
		t.Run(fmt.Sprint(seqs), func(t *testing.T) {
			ctx := recoveryContext(t)
			c := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{longConnMgr: c, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 5}}
			pulled := make(chan [2]int64, 1)
			requestWorker(t, c, func(req Message) *GeneralWsResp {
				p := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, p); err != nil {
					panic(err)
				}
				pulled <- [2]int64{p.SeqRanges[0].Begin, p.SeqRanges[0].End}
				return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", 6)})
			})
			receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
			fastPath := false
			m.pushTriggerAndSync(ctx, recoveryMsgs("chat", seqs...), func(context.Context, map[string]*sdkws.PullMsgs) error { fastPath = true; return nil })
			if !fastPath {
				t.Fatal("latest push waited for gap recovery")
			}
			select {
			case got := <-pulled:
				if got != [2]int64{6, 6} || seqs[1] == 6 {
					t.Fatalf("wrong gap: %v", got)
				}
			default:
				if seqs[1] != 6 {
					t.Fatal("no gap pull")
				}
			}
			if m.syncedMaxSeqs["chat"] != 7 {
				t.Fatal("gap recovery did not commit")
			}
		})
	}
}

func TestCancelledRequestDoesNotEnterTransportQueue(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	cancel()
	c := &LongConnMgr{send: make(chan Message, 100)}
	for i := 0; i < 100; i++ {
		if err := c.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{}, constant.GetNewestSeq, &sdkws.GetMaxSeqResp{}); err == nil {
			t.Fatal("cancelled request succeeded")
		}
	}
	if len(c.send) != 0 {
		t.Fatalf("queued %d cancelled requests", len(c.send))
	}
}

func TestFullTransportQueueHonorsDeadline(t *testing.T) {
	ctx, cancel := context.WithTimeout(recoveryContext(t), 20*time.Millisecond)
	defer cancel()
	c := &LongConnMgr{send: make(chan Message, 1)}
	c.send <- Message{}
	if err := c.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{}, constant.GetNewestSeq, &sdkws.GetMaxSeqResp{}); err == nil {
		t.Fatal("blocked queue succeeded")
	}
	if len(c.send) != 1 {
		t.Fatal("expired request entered full queue")
	}
}

func TestExpiredRequestIsNotWritten(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	cancel()
	c := &LongConnMgr{Syncer: NewWsRespAsyn()}
	// No connection is configured: accessing it would panic if cancellation is ignored.
	if _, err := c.sendAndWaitResp(ctx, &GeneralWsReq{ReqIdentifier: constant.PullMsgByRange}); err == nil {
		t.Fatal("expired request was sent")
	}
	if len(c.Syncer.wsNotification) != 0 {
		t.Fatal("expired request leaked response registration")
	}
}
