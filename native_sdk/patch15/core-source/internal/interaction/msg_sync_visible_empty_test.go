package interaction

import (
	"errors"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestEmptyPreviewFailureDoesNotAdvanceCheckpoint(t *testing.T) {
	for _, disk := range []bool{false, true} {
		t.Run(fmt.Sprint("disk=", disk), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			db := &recoveryVersionDB{}
			if disk {
				db.writeErr = errors.New("disk unavailable")
			}
			// checkpointFaultDB fails only the durable completion write.
			store := &checkpointFaultDB{recoveryVersionDB: db}
			if disk {
				store.failCompleted = 4
			}
			m := &MsgSyncer{ctx: ctx, longConnMgr: conn, syncedMaxSeqs: map[string]int64{}, db: store}
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if !disk {
					return &GeneralWsResp{ErrCode: 10001, ErrMsg: "boundary unavailable"}
				}
				return wireResponse(&msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{"sg_test": {IsEnd: true, EndSeq: 5}}})
			})
			batch := map[string][2]int64{"sg_test": {4, 4}}
			err := m.resolveEmptySyncPreviews(ctx, batch, map[string][2]int64{"sg_test": {1, 4}}, &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{"sg_test": {}}})
			if err == nil || m.syncedMaxSeqs["sg_test"] != 0 || len(batch) != 1 {
				t.Fatal("failed proof/write discarded pending work", err)
			}
		})
	}
}

func TestEmptyPreviewRequiresAuthoritativeInvisiblePrefix(t *testing.T) {
	for _, tc := range []struct {
		name              string
		lower             int64
		terminal, missing bool
		wantClosed        bool
	}{
		{"cleared_history", 5, true, false, true},
		{"inclusive_boundary_still_readable", 4, true, false, false},
		{"empty_without_boundary", 5, false, false, false},
		{"missing_boundary_packet", 5, true, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, longConnMgr: conn, syncedMaxSeqs: map[string]int64{}, db: &recoveryVersionDB{}}
			batch := map[string][2]int64{"sg_test": {4, 4}}
			visible := map[string][2]int64{"sg_test": {1, 4}}
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier != constant.PullMsgBySeqList {
					t.Error("unexpected request")
				}
				q := &msg.GetSeqMessageReq{}
				_ = proto.Unmarshal(req.Message.Data, q)
				p := &sdkws.PullMsgs{IsEnd: tc.terminal, EndSeq: tc.lower}
				if q.Order == sdkws.PullOrder_PullOrderAsc {
					p.EndSeq = 4
				}
				r := &msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{}}
				if !tc.missing {
					r.Msgs["sg_test"] = p
				}
				return wireResponse(r)
			})
			err := m.resolveEmptySyncPreviews(ctx, batch, visible, &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{"sg_test": {IsEnd: true, EndSeq: 4}}})
			if tc.missing && err == nil {
				t.Fatal("missing proof accepted")
			}
			if !tc.missing && err != nil {
				t.Fatal(err)
			}
			if tc.wantClosed {
				if len(batch) != 0 || m.syncedMaxSeqs["sg_test"] != 4 || visible["sg_test"][0] != 5 {
					t.Fatal("closed prefix not committed")
				}
			} else if len(batch) != 1 || m.syncedMaxSeqs["sg_test"] != 0 {
				t.Fatal("unproven gap acknowledged")
			}
		})
	}
}

func TestEmptyPreviewsRevalidateInOneBatchAndDoNotRepeat(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, syncedMaxSeqs: map[string]int64{}, db: &recoveryVersionDB{}}
	targets := map[string]int64{}
	requests := 0
	for n := 0; n < 100; n++ {
		targets[fmt.Sprintf("sg_%03d", n)] = 4
	}
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		requests++
		if req.Message.ReqIdentifier == constant.PullMsgByRange {
			r := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}}
			for id := range targets {
				r.Msgs[id] = &sdkws.PullMsgs{IsEnd: true, EndSeq: 4}
			}
			return wireResponse(r)
		}
		q := &msg.GetSeqMessageReq{}
		_ = proto.Unmarshal(req.Message.Data, q)
		if len(q.Conversations) != 100 || q.Order != sdkws.PullOrder_PullOrderDesc {
			t.Error("not batched")
		}
		r := &msg.GetSeqMessageResp{Msgs: map[string]*sdkws.PullMsgs{}}
		for id := range targets {
			r.Msgs[id] = &sdkws.PullMsgs{IsEnd: true, EndSeq: 5}
		}
		return wireResponse(r)
	})
	for n := 0; n < 2; n++ {
		if err := m.compareSeqsAndBatchSync(ctx, targets, 1); err != nil {
			t.Fatal(err)
		}
	}
	if requests != 2 {
		t.Fatalf("expected one preview and one boundary batch, got %d", requests)
	}
}
