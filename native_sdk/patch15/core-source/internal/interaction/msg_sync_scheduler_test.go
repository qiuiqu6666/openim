package interaction

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func TestLivePushPreemptsSyncWithoutConcurrentStateOwners(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	input := make(chan common.Cmd2Value, 8)
	started, live, resumed, done := make(chan struct{}), make(chan struct{}), make(chan struct{}), make(chan struct{})
	var owners, attempts atomic.Int32
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if owners.Add(1) != 1 {
				t.Error("concurrent sequence owners")
			}
			defer owners.Add(-1)
			if cmd.Cmd == constant.CmdPushMsg {
				close(live)
				return
			}
			if attempts.Add(1) == 1 {
				close(started)
			} else {
				close(resumed)
			}
			<-cmd.Ctx.Done()
		})
	}()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdWakeUpDataSync}
	<-started
	for i := 0; i < 5; i++ {
		input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdWakeUpDataSync}
	}
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
	select {
	case <-live:
	case <-time.After(time.Second):
		t.Fatal("sync blocked live push")
	}
	select {
	case <-resumed:
	case <-time.After(time.Second):
		t.Fatal("interrupted sync was lost")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("logout did not stop sync")
	}
	if attempts.Load() != 2 {
		t.Fatalf("duplicate sync signals queued %d jobs", attempts.Load())
	}
}

func TestLivePushArrivesWhileNativeSyncNetworkIsStalled(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	c := &LongConnMgr{send: make(chan Message, 4)}
	m := &MsgSyncer{ctx: ctx, loginUserID: "self", longConnMgr: c,
		recvCh: make(chan common.Cmd2Value, 4), conversationCh: make(chan common.Cmd2Value, 4),
		syncedMaxSeqs: map[string]int64{"chat": 5}}
	delivered := make(chan int64, 4)
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd == constant.CmdNewMsgCome {
			for _, msg := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs {
				delivered <- msg.Seq
			}
		}
		return nil
	})
	done := make(chan struct{})
	go func() { defer close(done); m.DoListener(ctx) }()
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdWakeUpDataSync}
	// Leave the sequence request unanswered. A live push must not wait for its
	// network timeout, and the catch-up request must resume after delivery.
	select {
	case <-c.send:
	case <-ctx.Done():
		t.Fatal("sync never started")
	}
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg,
		Value: &sdkws.PushMessages{Msgs: recoveryMsgs("chat", 6)}}
	select {
	case seq := <-delivered:
		if seq != 6 {
			t.Fatalf("unexpected sequence %d", seq)
		}
	case <-time.After(time.Second):
		t.Fatal("live message waited behind sync network request")
	}
	select {
	case <-c.send:
	case <-time.After(time.Second):
		t.Fatal("sync was not resumed")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("listener failed to exit")
	}
	if m.syncedMaxSeqs["chat"] != 6 {
		t.Fatal("live storage acknowledgement not committed")
	}
}

func TestReconnectDuringSyncIsRetained(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	input := make(chan common.Cmd2Value)
	started, release, reconnected, done := make(chan struct{}), make(chan struct{}), make(chan struct{}), make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == constant.CmdWakeUpDataSync {
				close(started)
				select {
				case <-release:
				case <-cmd.Ctx.Done():
				}
			} else {
				close(reconnected)
			}
		})
	}()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdWakeUpDataSync}
	<-started
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdConnSuccesss}
	close(release)
	select {
	case <-reconnected:
	case <-time.After(time.Second):
		t.Fatal("new connection event was discarded")
	}
	cancel()
	<-done
}

func TestShortSyncCompletesWithoutLivePushCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	input := make(chan common.Cmd2Value, 4)
	started, release, live, done := make(chan struct{}), make(chan struct{}), make(chan struct{}), make(chan struct{})
	var attempts atomic.Int32
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == constant.CmdPushMsg {
				close(live)
				return
			}
			attempts.Add(1)
			close(started)
			select {
			case <-release:
			case <-cmd.Ctx.Done():
				t.Error("short sync was cancelled")
			}
		})
	}()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdWakeUpDataSync}
	<-started
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
	time.Sleep(10 * time.Millisecond)
	close(release)
	select {
	case <-live:
	case <-time.After(time.Second):
		t.Fatal("live push blocked")
	}
	cancel()
	<-done
	if attempts.Load() != 1 {
		t.Fatal(attempts.Load())
	}
}
