package interaction

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
	"sync/atomic"
	"testing"
	"time"
)

func TestVisibilityPreflightYieldsBetweenConversations(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 1)}
	d := &checkpointFaultDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, boundary: model_struct.LocalConversation{MaxSeq: 10}}
	m := &MsgSyncer{ctx: ctx, db: d, longConnMgr: conn, recvCh: make(chan common.Cmd2Value), conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"a": 10, "b": 10}}
	boundaryStarted, release := make(chan struct{}), make(chan struct{})
	var probes int
	var live atomic.Bool
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if p, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation); ok && p.Msgs["live"] != nil {
			live.Store(true)
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.PullMsgBySeqList {
			probes++
			if probes == 1 {
				close(boundaryStarted)
				select {
				case <-release:
				case <-req.Ctx.Done():
					return &GeneralWsResp{ErrCode: 10001}
				}
			}
			if probes == 3 && !live.Load() {
				t.Error("live message waited behind every visibility probe")
			}
			p := &msg.GetSeqMessageReq{}
			if err := proto.Unmarshal(req.Message.Data, p); err != nil {
				panic(err)
			}
			return wireResponse(&msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{p.Conversations[0].ConversationID: {}}})
		}
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		r := p.SeqRanges[0]
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs(r.ConversationID, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20)})
	})
	finished := make(chan error, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, m.recvCh, func(cmd common.Cmd2Value) {
			if isBackgroundSyncCommand(cmd) {
				finished <- m.syncCompleteMessageRanges(cmd.Ctx, map[string][2]int64{"a": {11, 20}, "b": {11, 20}}, false)
			} else {
				m.handlePushMsgAndEventSafely(cmd)
			}
		}, func() bool { return true })
	}()
	t.Cleanup(func() { cancel(); <-done })
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	<-boundaryStarted
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg, Value: &sdkws.PushMessages{Msgs: recoveryMsgs("live", 1)}}
	close(release)
	select {
	case err := <-finished:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal("boundary recovery did not finish")
	}
	if probes != 4 || !live.Load() {
		t.Fatalf("unexpected progress probes=%d live=%v", probes, live.Load())
	}
}

func TestLivePushCannotStarveMaxSequenceDiscovery(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	input := make(chan common.Cmd2Value)
	started := make(chan context.Context, 3)
	release := make(chan struct{})
	live := make(chan struct{}, 40)
	finished := make(chan struct{}, 1)
	var attempts atomic.Int32
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if !isBackgroundSyncCommand(cmd) {
				live <- struct{}{}
				return
			}
			n := attempts.Add(1)
			started <- cmd.Ctx
			if n == 1 {
				<-cmd.Ctx.Done()
				return
			}
			select {
			case <-release:
				finished <- struct{}{}
			case <-cmd.Ctx.Done():
			}
		})
	}()
	t.Cleanup(func() { cancel(); <-done })
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	<-started
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
	<-live
	retry := <-started
	for n := 0; n < 35; n++ {
		input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
	}
	select {
	case <-retry.Done():
		t.Fatal("max-sequence retry was starved by live traffic")
	case <-time.After(150 * time.Millisecond):
	}
	close(release)
	select {
	case <-finished:
	case <-ctx.Done():
		t.Fatal("metadata never completed")
	}
	for n := 0; n < 35; n++ {
		select {
		case <-live:
		case <-ctx.Done():
			t.Fatal("live events not drained")
		}
	}
	if attempts.Load() != 2 {
		t.Fatal(attempts.Load())
	}
}

func TestInitialHistoryYieldsLivePushBetweenPages(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, db: &recoveryVersionDB{}, reinstalled: true, longConnMgr: conn, recvCh: make(chan common.Cmd2Value), conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
	pageStarted := make(chan int64, 3)
	releasePage := make(chan struct{})
	liveStored := make(chan struct{}, 1)
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if p, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation); ok && p.Msgs["live"] != nil {
			liveStored <- struct{}{}
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.GetNewestSeq {
			return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"history": 300, "history_b": 300}})
		}
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		r := p.SeqRanges[0]
		pageStarted <- r.Begin
		select {
		case <-releasePage:
		case <-req.Ctx.Done():
			return &GeneralWsResp{ErrCode: 10001}
		}
		var seqs []int64
		for seq := r.Begin; seq <= r.End; seq++ {
			seqs = append(seqs, seq)
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs(r.ConversationID, seqs...)})
	})
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, m.recvCh, m.handlePushMsgAndEventSafely, func() bool { return m.reinstalled })
	}()
	t.Cleanup(func() { cancel(); <-done })
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdConnSuccesss}
	if got := <-pageStarted; got != 201 {
		t.Fatal(got)
	}
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg, Value: &sdkws.PushMessages{Msgs: recoveryMsgs("live", 1)}}
	releasePage <- struct{}{}
	if got := <-pageStarted; got != 201 {
		t.Fatal(got)
	}
	select {
	case <-liveStored:
	default:
		t.Fatal("live push waited for all history pages")
	}
	releasePage <- struct{}{}
}

func TestContinuousLivePushCannotCancelEveryRecoveryPage(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, recvCh: make(chan common.Cmd2Value), conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"gap": 3}}
	pulls := make(chan Message, 3)
	release := make(chan struct{})
	storedGap := make(chan struct{}, 1)
	liveStored := make(chan int64, 64)
	var attempts atomic.Int32
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if p, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation); ok {
			if p.Msgs["gap"] != nil {
				storedGap <- struct{}{}
			}
			if p.Msgs["live"] != nil {
				liveStored <- p.Msgs["live"].Msgs[0].Seq
			}
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.GetNewestSeq {
			return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"gap": 13}})
		}
		n := attempts.Add(1)
		pulls <- req
		if n == 1 {
			<-req.Ctx.Done()
			return &GeneralWsResp{ErrCode: 10001}
		}
		select {
		case <-release:
		case <-req.Ctx.Done():
			return &GeneralWsResp{ErrCode: 10001}
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("gap", 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)})
	})
	done := make(chan struct{})
	go func() { defer close(done); runMessageSyncLoop(ctx, m.recvCh, m.handlePushMsgAndEventSafely) }()
	t.Cleanup(func() { cancel(); <-done })
	push := func(seq int64) {
		m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg, Value: &sdkws.PushMessages{Msgs: recoveryMsgs("live", seq)}}
	}
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	<-pulls
	push(1)
	select {
	case <-liveStored:
	case <-ctx.Done():
		t.Fatal("stalled first attempt blocked live push")
	}
	var retry Message
	select {
	case retry = <-pulls:
	case <-ctx.Done():
		t.Fatal("recovery was not retried")
	}
	for seq := int64(2); seq <= 40; seq++ {
		push(seq)
	}
	select {
	case <-retry.Ctx.Done():
		t.Fatal("continuous live ingress cancelled reserved progress")
	case <-time.After(150 * time.Millisecond):
	}
	close(release)
	select {
	case <-storedGap:
	case <-ctx.Done():
		t.Fatal("gap made no progress")
	}
	for seq := int64(2); seq <= 40; seq++ {
		select {
		case got := <-liveStored:
			if got != seq {
				t.Fatalf("live ordering: %d != %d", got, seq)
			}
		case <-ctx.Done():
			t.Fatal("live queue stranded after gap")
		}
	}
	if attempts.Load() != 2 {
		t.Fatalf("expected one bounded preemption, attempts=%d", attempts.Load())
	}
}
