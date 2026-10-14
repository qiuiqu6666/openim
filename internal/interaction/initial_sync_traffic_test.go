package interaction

import (
	"context"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestFirstLoginCompletesAndCommitsMessagesUnderLiveTraffic(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 4)}
	db := &recoveryVersionDB{}
	m := &MsgSyncer{ctx: ctx, db: db, reinstalled: true, loginUserID: "self", longConnMgr: conn,
		recvCh: make(chan common.Cmd2Value, 32), conversationCh: make(chan common.Cmd2Value, 32), syncedMaxSeqs: map[string]int64{}}
	started, release := make(chan struct{}), make(chan struct{})
	stored := make(chan int64, 32)
	starts := 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if initial, ok := cmd.Value.(sdk_struct.CmdMsgSyncInReinstall); ok {
			for _, messages := range initial.Msgs {
				for _, msg := range messages.Msgs {
					stored <- msg.Seq
				}
			}
			return nil
		}
		v, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
		if !ok {
			return nil
		}
		if cmd.Cmd == constant.CmdSyncFlag && v.SyncFlag == constant.AppDataSyncStart {
			starts++
			if starts == 1 {
				close(started)
			}
			select {
			case <-release:
				return cmd.Ctx.Err()
			case <-cmd.Ctx.Done():
				return cmd.Ctx.Err()
			}
		}
		for _, messages := range v.Msgs {
			for _, msg := range messages.Msgs {
				stored <- msg.Seq
			}
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.GetNewestSeq {
			return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 6}})
		}
		pull := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
			panic(err)
		}
		var seqs []int64
		for seq := pull.SeqRanges[0].Begin; seq <= pull.SeqRanges[0].End; seq++ {
			seqs = append(seqs, seq)
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)})
	})
	done := make(chan struct{})
	allHandled := make(chan struct{})
	commitsFinished := make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, m.recvCh, func(cmd common.Cmd2Value) {
			if cmd.Cmd == "testCommitBarrier" {
				close(commitsFinished)
				return
			}
			m.handlePushMsgAndEventSafely(cmd)
			if cmd.Cmd == constant.CmdPushMsg && cmd.Value.(*sdkws.PushMessages).Msgs["chat"].Msgs[0].Seq == 26 {
				close(allHandled)
			}
		}, func() bool { return m.reinstalled })
	}()
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdConnSuccesss}
	<-started
	for seq := int64(7); seq <= 26; seq++ {
		m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg, Value: &sdkws.PushMessages{Msgs: recoveryMsgs("chat", seq)}}
	}
	select {
	case <-stored:
		t.Fatal("messages handled before first-login metadata was ready")
	case <-time.After(30 * time.Millisecond):
	}
	close(release)
	seen := make(map[int64]bool)
	for n := 0; n < 26; n++ {
		select {
		case got := <-stored:
			if got < 1 || got > 26 || seen[got] {
				t.Fatalf("unexpected/duplicate sequence %d", got)
			}
			seen[got] = true
		case <-ctx.Done():
			t.Fatal("initial sync or queued live messages did not finish")
		}
	}
	select {
	case <-allHandled:
	case <-ctx.Done():
		t.Fatal("live message commit never acknowledged")
	}
	// Pushes can now be handled at the first page boundary and journal gaps.
	// Receipt observation alone precedes the worker's durable checkpoint write.
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: "testCommitBarrier"}
	select {
	case <-commitsFinished:
	case <-ctx.Done():
		t.Fatal("range checkpoint never committed")
	}
	cancel()
	<-done
	if !db.installed || m.reinstalled || m.syncedMaxSeqs["chat"] != 26 || starts != 1 {
		t.Fatalf("bootstrap not committed: installed=%v reinstall=%v seq=%d starts=%d", db.installed, m.reinstalled, m.syncedMaxSeqs["chat"], starts)
	}
}
