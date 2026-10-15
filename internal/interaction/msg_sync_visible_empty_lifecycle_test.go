package interaction

import (
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

// Exercise the scheduler and delivery receipts, rather than only the boundary helper.
func TestInvisiblePrefixLifecycleDoesNotSkipNewMessages(t *testing.T) {
	for _, scenario := range []string{"clear_then_new", "rejoin_stale_upper", "reconnect_persisted_checkpoint"} {
		t.Run(scenario, func(t *testing.T) {
			ctx := recoveryContext(t)
			store := &checkpointFaultDB{recoveryVersionDB: &recoveryVersionDB{installed: true}}
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, db: store, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			lower, upper := int64(5), int64(4)
			offline := false
			delivered := map[int64]int{}
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				for _, batch := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
					for _, row := range batch.Msgs {
						delivered[row.Seq]++
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if offline {
					return &GeneralWsResp{ErrCode: 10001, ErrMsg: "connection lost"}
				}
				if req.Message.ReqIdentifier == constant.PullMsgBySeqList {
					q := &msg.GetSeqMessageReq{}
					if err := proto.Unmarshal(req.Message.Data, q); err != nil {
						panic(err)
					}
					p := &sdkws.PullMsgs{}
					seq := q.Conversations[0].Seqs[0]
					if q.Order == sdkws.PullOrder_PullOrderDesc && seq <= lower {
						p.IsEnd, p.EndSeq = true, lower
					}
					if q.Order == sdkws.PullOrder_PullOrderAsc && seq >= upper {
						p.IsEnd, p.EndSeq = true, upper
					}
					return wireResponse(&msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{"chat": p}})
				}
				q := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, q); err != nil {
					panic(err)
				}
				r := q.SeqRanges[0]
				var seqs []int64
				for s := r.Begin; s <= r.End; s++ {
					if s >= lower && s <= upper {
						seqs = append(seqs, s)
					}
				}
				return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)})
			})
			if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": 4}, 1); err != nil {
				t.Fatal(err)
			}
			if m.syncedMaxSeqs["chat"] != 4 || len(delivered) != 0 {
				t.Fatal("old invisible prefix was not closed safely")
			}
			if scenario == "rejoin_stale_upper" {
				// Membership reopens at seq 5, while the local cache still says max 4.
				store.boundary = model_struct.LocalConversation{MinSeq: 5, MaxSeq: 4}
			}
			if scenario == "reconnect_persisted_checkpoint" {
				m = &MsgSyncer{ctx: ctx, db: store, longConnMgr: conn, conversationCh: m.conversationCh, syncedMaxSeqs: map[string]int64{}}
				if err := m.loadMessageCheckpoints(ctx, []string{"chat"}); err != nil {
					t.Fatal(err)
				}
				offline = true
				if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": 7}, 1); err == nil {
					t.Fatal("outage accepted as completion")
				}
				if m.syncedMaxSeqs["chat"] != 4 {
					t.Fatal("outage advanced checkpoint")
				}
				offline = false
			}
			upper = 7
			if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": upper}, 1); err != nil {
				t.Fatal(err)
			}
			for seq := int64(5); seq <= upper; seq++ {
				if delivered[seq] != 1 {
					t.Fatalf("normal seq %d delivered %d times", seq, delivered[seq])
				}
			}
			if m.syncedMaxSeqs["chat"] != upper {
				t.Fatalf("checkpoint=%d", m.syncedMaxSeqs["chat"])
			}
			if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": upper}, 1); err != nil {
				t.Fatal(err)
			}
			for seq, count := range delivered {
				if count != 1 {
					t.Fatalf("seq %d repeated after completion", seq)
				}
			}
		})
	}
}
