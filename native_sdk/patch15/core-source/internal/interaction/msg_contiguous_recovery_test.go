package interaction

import (
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

// The peer has stopped sending. A range server honors exactly the wire request;
// it does not help the client by returning messages outside its requested tail.
func TestReconnectRecoversLatestWindowWithoutNextPush(t *testing.T) {
	for _, count := range []int64{10, 100, 1000, 100000000} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 3}}
			stored := make(map[int64]bool)
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				if cmd.Cmd == constant.CmdNewMsgCome {
					for _, row := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs {
						stored[row.Seq] = true
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.GetNewestSeq {
					return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 3 + count}})
				}
				p := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, p); err != nil {
					panic(err)
				}
				resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}}
				for _, r := range p.SeqRanges {
					if r.End-r.Begin+1 > SplitPullMsgNum {
						t.Errorf("unbounded batch: %v", r)
					}
					var seqs []int64
					for seq := r.Begin; seq <= r.End && int64(len(seqs)) < r.Num; seq++ {
						seqs = append(seqs, seq)
					}
					resp.Msgs[r.ConversationID] = recoveryMsgs(r.ConversationID, seqs...)[r.ConversationID]
				}
				return wireResponse(resp)
			})
			m.doConnected(ctx)
			if len(stored) != int(min(count, recentMessageWindow)) {
				t.Fatalf("offline rows persisted = %d/%d, cursor = %d", len(stored), count, m.syncedMaxSeqs["chat"])
			}
			if count > recentMessageWindow && m.syncedMaxSeqs["chat"] != 3 {
				t.Fatal("sparse tail advanced continuous checkpoint")
			}
			for seq := max(int64(4), 4+count-recentMessageWindow); seq <= 3+count; seq++ {
				if !stored[seq] {
					t.Fatalf("missing seq %d", seq)
				}
			}
		})
	}
}

func TestContiguousPartialAndEmptyResponsesCannotConsumeGap(t *testing.T) {
	for _, seqs := range [][]int64{nil, {13}, {4, 5, 7, 8, 9, 10, 11, 12, 13}, {4, 4, 5, 6, 7, 8, 9, 10, 11, 12}} {
		t.Run(fmt.Sprint(seqs), func(t *testing.T) {
			m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 3}}
			receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
			err := m.commitPulledMessages(recoveryContext(t), &sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)}, map[string][2]int64{"chat": {4, 13}}, 0)
			if err == nil || m.syncedMaxSeqs["chat"] != 3 {
				t.Fatalf("incomplete response accepted: error=%v cursor=%d", err, m.syncedMaxSeqs["chat"])
			}
		})
	}
}
