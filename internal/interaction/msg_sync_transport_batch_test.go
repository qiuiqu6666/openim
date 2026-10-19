package interaction

import (
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
	"testing"
)

func TestRecoveryTransportBatchesEightFullPagesWithoutLosingCoverage(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
	var ids []string
	pending := map[string][][2]int64{}
	for i := 0; i < 8; i++ {
		id := fmt.Sprintf("chat%d", i)
		ids = append(ids, id)
		pending[id] = [][2]int64{{1, 100}}
	}
	stored := map[string]int{}
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		for id, packet := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
			stored[id] += len(packet.Msgs)
		}
		return nil
	})
	requests := 0
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		requests++
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		if len(p.SeqRanges) != 8 {
			t.Errorf("expected eight independent pages, got %d", len(p.SeqRanges))
		}
		for _, r := range p.SeqRanges {
			if r.Num != 100 || r.Begin != 1 || r.End != 100 {
				t.Errorf("changed conversation page: %v", r)
			}
		}
		return requestedRecoveryResponse(t, req)
	})
	failures := m.pullMissingRecoveryBatch(ctx, m.nextRecoveryBatch(ids, pending), 0)
	if len(failures) != 0 {
		t.Fatal(failures)
	}
	if requests != 1 {
		t.Fatalf("requests=%d", requests)
	}
	for _, id := range ids {
		if stored[id] != 100 || m.syncedMaxSeqs[id] != 100 {
			t.Fatalf("lost coverage %s: rows=%d seq=%d", id, stored[id], m.syncedMaxSeqs[id])
		}
	}
}
