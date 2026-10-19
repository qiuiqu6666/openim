package interaction

import (
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
	"testing"
)

func TestIncompleteRecoveryBatchesBoundaryChecksWithoutWaivingUnknownGaps(t *testing.T) {
	for _, explicit := range []bool{false, true} {
		t.Run(fmt.Sprint(explicit), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			var ids []string
			pending := map[string][][2]int64{}
			for i := 0; i < 8; i++ {
				id := fmt.Sprintf("chat%d", i)
				ids = append(ids, id)
				pending[id] = [][2]int64{{1, 2}}
			}
			boundaries := 0
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.PullMsgBySeqList {
					boundaries++
					p := &msg.GetSeqMessageReq{}
					if err := proto.Unmarshal(req.Message.Data, p); err != nil {
						panic(err)
					}
					packets := map[string]*sdkws.PullMsgs{}
					for _, v := range p.Conversations {
						packets[v.ConversationID] = &sdkws.PullMsgs{IsEnd: explicit && p.Order == sdkws.PullOrder_PullOrderAsc, EndSeq: 0}
					}
					return wireResponse(&msg.GetSeqMessageResp{Msgs: packets})
				}
				return wireResponse(&sdkws.PullMessageBySeqsResp{})
			})
			failures := m.recoverRecentMessagePages(ctx, ids, pending, false, 0)
			if boundaries != 2 {
				t.Fatalf("wanted two batched directional checks, got %d", boundaries)
			}
			if explicit && len(failures) != 0 {
				t.Fatalf("explicit empty boundary failed: %v", failures)
			}
			if !explicit && len(failures) != 8 {
				t.Fatalf("unknown gaps incorrectly accepted: %v", failures)
			}
			for _, id := range ids {
				if m.syncedMaxSeqs[id] != 0 {
					t.Fatal("unreceived message checkpoint advanced")
				}
			}
		})
	}
}
