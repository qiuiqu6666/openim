package interaction

import (
	"context"
	"errors"
	"reflect"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestPeriodicReconciliationRecoversMissingTailWithoutPush(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 1)}
	conn.SetConnectionStatus(Connected)
	m := &MsgSyncer{ctx: ctx, loginUserID: "self", longConnMgr: conn,
		recvCh: make(chan common.Cmd2Value, 8), conversationCh: make(chan common.Cmd2Value),
		syncedMaxSeqs: map[string]int64{"chat": 998}}
	delivered := make(chan []int64, 2)
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd != constant.CmdNewMsgCome {
			t.Errorf("periodic check started metadata or sync lifecycle: %s", cmd.Cmd)
			return nil
		}
		var seqs []int64
		for _, msg := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs {
			seqs = append(seqs, msg.Seq)
		}
		delivered <- seqs
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.GetNewestSeq {
			return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 1000}})
		}
		pull := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
			panic(err)
		}
		if len(pull.SeqRanges) != 1 || pull.SeqRanges[0].Begin < 999 || pull.SeqRanges[0].End > 1000 || pull.SeqRanges[0].Num != 1 {
			t.Errorf("incorrect tail recovery range: %v", pull.SeqRanges)
		}
		return requestedRecoveryResponse(t, req)
	})
	ticks, done := make(chan time.Time), make(chan struct{})
	go func() { defer close(done); m.listenWithReconciliation(ctx, ticks) }()
	t.Cleanup(func() { cancel(); <-done })
	ticks <- time.Now()
	var got []int64
	for len(got) < 2 {
		select {
		case page := <-delivered:
			got = append(got, page...)
		case <-ctx.Done():
			t.Fatal("online device waited for a new push to catch up")
		}
	}
	if !reflect.DeepEqual(got, []int64{1000, 999}) {
		t.Fatalf("missed latest-first recovery: %v", got)
	}
}

func TestPeriodicReconciliationSkipsUnavailableAndUninitializedSessions(t *testing.T) {
	for _, state := range []string{"disconnected", "background", "cancelled"} {
		t.Run(state, func(t *testing.T) {
			ctx, cancel := context.WithCancel(recoveryContext(t))
			defer cancel()
			conn := &LongConnMgr{send: make(chan Message, 1)}
			conn.SetConnectionStatus(Connected)
			m := &MsgSyncer{longConnMgr: conn}
			switch state {
			case "disconnected":
				conn.SetConnectionStatus(Closed)
			case "background":
				conn.SetBackground(true)
			case "cancelled":
				cancel()
			}
			var requests atomic.Int32
			requestWorker(t, conn, func(Message) *GeneralWsResp {
				requests.Add(1)
				return wireResponse(&sdkws.GetMaxSeqResp{})
			})
			m.doMessageSeqReconciliation(ctx)
			if requests.Load() != 0 {
				t.Fatal("idle maintenance requested data in an unavailable session")
			}
		})
	}
}

func TestPeriodicReconciliationStopsPullWhenAppBackgroundsDuringProbe(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	conn.SetConnectionStatus(Connected)
	m := &MsgSyncer{longConnMgr: conn, syncedMaxSeqs: map[string]int64{"chat": 998}}
	var requests atomic.Int32
	requestWorker(t, conn, func(Message) *GeneralWsResp {
		requests.Add(1)
		conn.SetBackground(true)
		return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 1000}})
	})
	m.doMessageSeqReconciliation(ctx)
	if requests.Load() != 1 || m.syncedMaxSeqs["chat"] != 998 {
		t.Fatal("background transition started a pull or advanced the sequence")
	}
}

func TestPeriodicReconciliationRetriesFailedProbePullAndStorage(t *testing.T) {
	for _, failure := range []string{"probe", "pull", "storage"} {
		t.Run(failure, func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			conn.SetConnectionStatus(Connected)
			m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value),
				syncedMaxSeqs: map[string]int64{"chat": 998}}
			var failed atomic.Bool
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				if cmd.Cmd != constant.CmdNewMsgCome {
					t.Errorf("periodic failure triggered full sync: %s", cmd.Cmd)
				}
				if failure == "storage" && failed.CompareAndSwap(false, true) {
					return errors.New("disk unavailable")
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				probe := req.Message.ReqIdentifier == constant.GetNewestSeq
				if ((probe && failure == "probe") || (!probe && failure == "pull")) && failed.CompareAndSwap(false, true) {
					return &GeneralWsResp{ErrCode: 10001, ErrMsg: "temporary failure"}
				}
				if probe {
					return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 1000}})
				}
				return requestedRecoveryResponse(t, req)
			})
			m.doMessageSeqReconciliation(ctx)
			if !failed.Load() || m.syncedMaxSeqs["chat"] != 998 {
				t.Fatal("failure consumed the missing range")
			}
			m.doMessageSeqReconciliation(ctx)
			if m.syncedMaxSeqs["chat"] != 1000 {
				t.Fatal("next reconciliation did not recover")
			}
		})
	}
}

func TestPeriodicReconciliationQueueSkipsOfflineTicksAndStopsWhenBusy(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	input := make(chan common.Cmd2Value, 1)
	ticks := make(chan time.Time)
	done := make(chan struct{})
	var ready atomic.Bool
	go func() {
		defer close(done)
		runMessageSeqReconciliation(ctx, ticks, ready.Load, input)
	}()
	ticks <- time.Now()
	// The next tick cannot be received until the previous offline tick exits.
	ticks <- time.Now()
	if len(input) != 0 {
		t.Fatal("offline tick enqueued reconciliation")
	}
	ready.Store(true)
	ticks <- time.Now()
	ticks <- time.Now()
	ticks <- time.Now()
	if len(input) != 1 {
		t.Fatal("maintenance did not coalesce on a full queue")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("logout left maintenance blocked behind the queue")
	}
}

func TestPeriodicReconciliationCannotReplaceForegroundOrReconnect(t *testing.T) {
	periodic := common.Cmd2Value{Cmd: cmdReconcileMessageSeq}
	for _, cmd := range []string{constant.CmdConnSuccesss, constant.CmdWakeUpDataSync, constant.CmdIMMessageSync} {
		pending := &common.Cmd2Value{Cmd: cmd}
		if got := coalesceMessageSync(pending, periodic); got != pending {
			t.Fatalf("maintenance replaced %s", cmd)
		}
		if got := coalesceMessageSync(&periodic, *pending); got.Cmd != cmd {
			t.Fatalf("maintenance hid %s", cmd)
		}
	}
}

func TestQueuedReconnectKeepsPriorityOverLightweightSync(t *testing.T) {
	ordered := []string{constant.CmdConnSuccesss, constant.CmdWakeUpDataSync, constant.CmdIMMessageSync, cmdReconcileMessageSeq}
	for i, stronger := range ordered {
		for _, weaker := range ordered[i+1:] {
			pending := &common.Cmd2Value{Cmd: stronger}
			if got := coalesceMessageSync(pending, common.Cmd2Value{Cmd: weaker}); got != pending {
				t.Errorf("%s replaced pending %s", weaker, stronger)
			}
			if got := coalesceMessageSync(&common.Cmd2Value{Cmd: weaker}, *pending); got.Cmd != stronger {
				t.Errorf("%s did not replace pending %s", stronger, weaker)
			}
		}
	}
}

func TestForegroundAndLivePushPreemptReconciliationWithoutConcurrentOwners(t *testing.T) {
	for _, cmd := range []string{constant.CmdWakeUpDataSync, constant.CmdConnSuccesss, constant.CmdPushMsg} {
		t.Run(cmd, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			input := make(chan common.Cmd2Value, 8)
			started, handled, done := make(chan struct{}), make(chan struct{}), make(chan struct{})
			var owners atomic.Int32
			go func() {
				defer close(done)
				runMessageSyncLoop(ctx, input, func(job common.Cmd2Value) {
					if owners.Add(1) != 1 {
						t.Error("concurrent sequence mutation")
					}
					defer owners.Add(-1)
					if job.Cmd == cmdReconcileMessageSeq {
						select {
						case <-started:
						default:
							close(started)
						}
						<-job.Ctx.Done()
					} else {
						close(handled)
					}
				})
			}()
			t.Cleanup(func() { cancel(); <-done })
			input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdReconcileMessageSeq}
			<-started
			for i := 0; i < 3; i++ {
				input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdReconcileMessageSeq}
			}
			input <- common.Cmd2Value{Ctx: ctx, Cmd: cmd}
			select {
			case <-handled:
			case <-time.After(time.Second):
				t.Fatal("maintenance blocked foreground recovery or push")
			}
		})
	}
}
