package interaction

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestLivePushAcrossLargeGapDeliveredBeforeHistory(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{ctx: ctx, recvCh: make(chan common.Cmd2Value, 1), conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 3}}
	delivered := false
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd == constant.CmdNewMsgCome {
			p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
			delivered = p.Msgs["chat"].Msgs[0].Seq == 150003 && p.Recovery
		}
		return nil
	})
	m.pushTriggerAndSync(ctx, recoveryMsgs("chat", 150003), m.triggerConversation)
	if !delivered {
		t.Fatal("latest push was withheld behind 150000 historical messages")
	}
	if m.syncedMaxSeqs["chat"] != 3 || m.checkpoints["chat"].Target != 150003 {
		t.Fatal("tail delivery consumed the historical recovery obligation")
	}
	select {
	case <-m.recvCh:
	default:
		t.Fatal("history recovery not scheduled")
	}
}

func TestLatestTailCommittedBeforeOldestPageAndCheckpointDoesNotJump(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 3}}
	latest := false
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if p, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation); ok && p.Msgs["chat"] != nil {
			for _, row := range p.Msgs["chat"].Msgs {
				if row.Seq == 150003 {
					latest = true
				}
			}
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		r := p.SeqRanges[0]
		if r.Begin == 4 {
			if !latest {
				t.Error("old history started before delivering the tail")
			}
			if m.syncedMaxSeqs["chat"] != 3 {
				t.Error("latest tail advanced continuous checkpoint")
			}
			cancel()
			return &GeneralWsResp{ErrCode: 10001}
		}
		var seqs []int64
		for s := r.Begin; s <= r.End; s++ {
			seqs = append(seqs, s)
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)})
	})
	_ = m.syncCompleteMessageRanges(ctx, map[string][2]int64{"chat": {4, 150003}}, false)
	if !latest {
		t.Fatal("tail was not delivered before interrupted old history")
	}
}
