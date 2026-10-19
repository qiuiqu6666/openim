package interaction

import (
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestRecoveryBatchesVisibilityAndSmallGapsWithoutDuplicateRows(t *testing.T) {
	for _, missingBoundary := range []bool{false, true} {
		t.Run(fmt.Sprint("missingBoundary=", missingBoundary), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			d := &checkpointFaultDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, boundary: model_struct.LocalConversation{MaxSeq: 1}}
			m := &MsgSyncer{ctx: ctx, db: d, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			targets := make(map[string]int64)
			for n := 0; n < 30; n++ {
				id := fmt.Sprintf("sg_%03d", n)
				targets[id] = 6
				m.syncedMaxSeqs[id] = 3
			}
			boundaries, pulls := 0, 0
			stored := make(map[string]map[int64]bool)
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				for id, packet := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
					if stored[id] == nil {
						stored[id] = make(map[int64]bool)
					}
					for _, row := range packet.Msgs {
						if row.Seq < 4 || row.Seq > 6 || stored[id][row.Seq] {
							t.Errorf("invisible or duplicate row %s/%d", id, row.Seq)
						}
						stored[id][row.Seq] = true
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.PullMsgBySeqList {
					boundaries++
					p := &msg.GetSeqMessageReq{}
					if err := proto.Unmarshal(req.Message.Data, p); err != nil {
						panic(err)
					}
					resp := &msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{}}
					for _, row := range p.Conversations {
						if missingBoundary && row.ConversationID == "sg_000" {
							continue
						}
						end := int64(4)
						if p.Order == sdkws.PullOrder_PullOrderAsc {
							end = 6
						}
						resp.Msgs[row.ConversationID] = &sdkws.PullMsgs{IsEnd: true, EndSeq: end}
					}
					return wireResponse(resp)
				}
				pulls++
				p := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, p); err != nil {
					panic(err)
				}
				rows := int64(0)
				for _, r := range p.SeqRanges {
					rows += r.Num
					if r.Num != r.End-r.Begin+1 {
						t.Error("range was silently cropped")
					}
				}
				if rows > 100 {
					t.Fatalf("response budget expanded: %d", rows)
				}
				return requestedRecoveryResponse(t, req)
			})
			err := m.compareSeqsAndBatchSync(ctx, targets, 1)
			if (err != nil) != missingBoundary {
				t.Fatalf("wrong boundary failure: %v", err)
			}
			if boundaries != 2 || pulls != 5 {
				t.Fatalf("boundary/pull requests=%d/%d", boundaries, pulls)
			}
			for id := range targets {
				want := 3
				if missingBoundary && id == "sg_000" {
					want = 0
				}
				if len(stored[id]) != want {
					t.Fatalf("lost messages for %s: %v", id, stored[id])
				}
			}
		})
	}
}
