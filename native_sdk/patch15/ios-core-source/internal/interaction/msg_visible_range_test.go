package interaction

import (
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
	"testing"
)

func TestVisibilityRecoveryUsesFreshBoundaries(t *testing.T) {
	for _, tc := range []struct {
		name                                                       string
		completed, cachedMax, target, visibleMin, visibleMax, want int64
		ambiguous                                                  bool
	}{
		{name: "stale upper bound", completed: 10, cachedMax: 10, target: 20, visibleMin: 1, visibleMax: 20, want: 20},
		{name: "expired prefix", target: 600, visibleMin: 501, visibleMax: 600, want: 600},
		{name: "permission upper bound", completed: 10, cachedMax: 10, target: 20, visibleMin: 1, visibleMax: 15, want: 15},
		{name: "ambiguous empty prefix", target: 600, visibleMin: 501, visibleMax: 600, want: 0, ambiguous: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := recoveryContext(t)
			d := &checkpointFaultDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, boundary: model_struct.LocalConversation{MaxSeq: tc.cachedMax}}
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, db: d, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": tc.completed}}
			delivered, pulls, probes := 0, 0, 0
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				for _, batch := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
					for _, row := range batch.Msgs {
						if row.Seq < tc.visibleMin || row.Seq > tc.visibleMax {
							t.Errorf("delivered invisible seq %d", row.Seq)
						}
						delivered++
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.PullMsgBySeqList {
					probes++
					p := &msg.GetSeqMessageReq{}
					if err := proto.Unmarshal(req.Message.Data, p); err != nil {
						panic(err)
					}
					bound := &sdkws.PullMsgs{}
					seq := p.Conversations[0].Seqs[0]
					if !tc.ambiguous {
						if p.Order == sdkws.PullOrder_PullOrderDesc && seq < tc.visibleMin {
							bound.IsEnd = true
							bound.EndSeq = tc.visibleMin
						}
						if p.Order == sdkws.PullOrder_PullOrderAsc && seq > tc.visibleMax {
							bound.IsEnd = true
							bound.EndSeq = tc.visibleMax
						}
					}
					return wireResponse(&msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{"chat": bound}})
				}
				pulls++
				p := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, p); err != nil {
					panic(err)
				}
				r := p.SeqRanges[0]
				var seqs []int64
				for s := r.Begin; s <= r.End; s++ {
					if s >= tc.visibleMin && s <= tc.visibleMax {
						seqs = append(seqs, s)
					}
				}
				return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)})
			})
			err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": tc.target}, 1)
			if (err != nil) != tc.ambiguous {
				t.Fatalf("unexpected sync result: %v", err)
			}
			if m.syncedMaxSeqs["chat"] != tc.want || m.checkpoints["chat"].Target != tc.target {
				t.Fatalf("lost coverage/target: %+v", m.checkpoints["chat"])
			}
			wantRows := int(tc.want - max(tc.completed, tc.visibleMin-1))
			if wantRows < 0 {
				wantRows = 0
			}
			if delivered != wantRows {
				t.Fatalf("delivered=%d want=%d", delivered, wantRows)
			}
			if probes != 2 {
				t.Fatalf("boundary resolution must be bounded: %d", probes)
			}
			if !tc.ambiguous && tc.want == tc.target {
				previous := pulls
				if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": tc.target}, 1); err != nil {
					t.Fatal(err)
				}
				if pulls != previous {
					t.Fatal("complete interval was fetched again")
				}
			}
		})
	}
}
