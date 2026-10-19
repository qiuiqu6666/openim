package interaction

import (
	"testing"

	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestEmptyPreviewClosesProvenInvisibleSuffixWithoutSkippingOlderGaps(t *testing.T) {
	for _, tc := range []struct {
		target, upper, completed int64
		covered                  [][2]int64
	}{
		{11, 7, 7, nil}, {171, 167, 0, [][2]int64{{72, 167}}},
		{9, 5, 5, nil}, {552, 548, 0, [][2]int64{{453, 548}}},
	} {
		ctx := recoveryContext(t)
		conn := &LongConnMgr{send: make(chan Message, 1)}
		m := &MsgSyncer{ctx: ctx, longConnMgr: conn, db: &recoveryVersionDB{}, syncedMaxSeqs: map[string]int64{"sg_heat": tc.completed}, checkpoints: map[string]messageCheckpoint{"sg_heat": {Completed: tc.completed, Target: tc.target, Covered: tc.covered}}}
		requestWorker(t, conn, func(req Message) *GeneralWsResp {
			q := &msg.GetSeqMessageReq{}
			_ = proto.Unmarshal(req.Message.Data, q)
			end := int64(1)
			if q.Order == sdkws.PullOrder_PullOrderAsc {
				end = tc.upper
			}
			return wireResponse(&msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{"sg_heat": {IsEnd: true, EndSeq: end}}})
		})
		batch := map[string][2]int64{"sg_heat": {tc.target, tc.target}}
		visible := map[string][2]int64{"sg_heat": {tc.completed + 1, tc.target}}
		resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{"sg_heat": {IsEnd: true, EndSeq: tc.upper}}}
		if err := m.resolveEmptySyncPreviews(ctx, batch, visible, resp); err != nil {
			t.Fatal(err)
		}
		if len(batch) != 0 || (m.syncedMaxSeqs["sg_heat"] < tc.target && !m.messageAlreadyCovered("sg_heat", tc.target)) {
			t.Fatalf("suffix still retried: target=%d state=%+v", tc.target, m.checkpoints["sg_heat"])
		}
		if tc.completed == 0 && m.syncedMaxSeqs["sg_heat"] != 0 {
			t.Fatal("acknowledged unseen older history")
		}
	}
}
