package interaction

import (
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
	"testing"
)

func TestExistingOldestMessageCatchesUpWithoutClearingData(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 1}}
	committed := 0
	seen := make(map[int64]bool)
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		for _, row := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs {
			if !seen[row.Seq] {
				seen[row.Seq] = true
				committed++
			}
		}
		return nil
	})
	next := int64(2)
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		r := p.SeqRanges[0]
		tail := r.Begin == 3975 && r.End == 3994 && next == 2
		if (!tail && r.Begin != next) || r.End-r.Begin+1 > 100 || r.Num != r.End-r.Begin+1 {
			t.Errorf("wrong recovery range: %v", r)
		}
		var seqs []int64
		for s := r.Begin; s <= r.End; s++ {
			seqs = append(seqs, s)
		}
		if !tail {
			next = r.End + 1
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)})
	})
	if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": 3994}, 1); err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["chat"] != 3994 {
		t.Fatal("catch-up did not commit")
	}
	if committed != 3993 {
		t.Fatalf("recovered %d/3993 rows", committed)
	}
}

func TestTailRangePreservesNotificationAndGapOrder(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{longConnMgr: conn}
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		if p.Order != sdkws.PullOrder_PullOrderAsc {
			t.Error("changed normal event ordering")
		}
		for _, r := range p.SeqRanges {
			want := int64(6)
			if r.Begin != want || r.End != 100 {
				t.Errorf("wrong range: %v", r)
			}
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{})
	})
	if _, err := m.pullMsgBySeqRange(ctx, map[string][2]int64{"chat": {6, 100}, "n_event": {6, 100}}, 10); err != nil {
		t.Fatal(err)
	}
}
