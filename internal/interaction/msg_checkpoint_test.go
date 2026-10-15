package interaction

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

type checkpointFaultDB struct {
	*recoveryVersionDB
	failCompleted int64
	boundary      model_struct.LocalConversation
}

func (d *checkpointFaultDB) SetVersionSync(ctx context.Context, row *model_struct.LocalVersionSync) error {
	var state messageCheckpoint
	if row.VersionID != "" {
		if err := json.Unmarshal([]byte(row.VersionID), &state); err != nil {
			return err
		}
	}
	if d.failCompleted > 0 && state.Completed == d.failCompleted {
		return errors.New("checkpoint disk failure")
	}
	return d.recoveryVersionDB.SetVersionSync(ctx, row)
}
func (d *checkpointFaultDB) GetConversation(context.Context, string) (*model_struct.LocalConversation, error) {
	c := d.boundary
	return &c, nil
}

func TestContiguousCheckpointFailureRestoresPendingAfterRestart(t *testing.T) {
	ctx := recoveryContext(t)
	d := &checkpointFaultDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, failCompleted: 6}
	m := &MsgSyncer{db: d, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 5}}
	receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
	resp := &sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", 6)}
	if err := m.commitPulledMessages(ctx, resp, map[string][2]int64{"chat": {6, 6}}, 0); err == nil {
		t.Fatal("checkpoint failure swallowed")
	}
	if m.syncedMaxSeqs["chat"] != 5 {
		t.Fatal("uncommitted checkpoint advanced")
	}
	restarted, err := NewMsgSyncer(ctx, m.conversationCh, nil, "self", nil, d, 0)
	if err != nil {
		t.Fatal(err)
	}
	if restarted.syncedMaxSeqs["chat"] != 5 || restarted.checkpoints["chat"].Target != 6 {
		t.Fatal("restart lost pending page")
	}
	d.failCompleted = 0
	if err := restarted.commitPulledMessages(ctx, resp, map[string][2]int64{"chat": {6, 6}}, 0); err != nil {
		t.Fatal(err)
	}
	if restarted.syncedMaxSeqs["chat"] != 6 {
		t.Fatal("retry failed")
	}
}

func TestContiguousVisibleBoundariesAndFailedConversationIsolation(t *testing.T) {
	ctx := recoveryContext(t)
	d := &checkpointFaultDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, boundary: model_struct.LocalConversation{MinSeq: 6, MaxSeq: 15}}
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{db: d, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"a": 3, "b": 3}}
	stored := 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		for _, p := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
			stored += len(p.Msgs)
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.PullMsgBySeqList {
			p := &msg.GetSeqMessageReq{}
			if err := proto.Unmarshal(req.Message.Data, p); err != nil {
				panic(err)
			}
			packets := make(map[string]*sdkws.PullMsgs)
			for _, row := range p.Conversations {
				packets[row.ConversationID] = &sdkws.PullMsgs{IsEnd: p.Order == sdkws.PullOrder_PullOrderAsc, EndSeq: 15}
			}
			return wireResponse(&msg.GetSeqMessageResp{Msgs: packets})
		}
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		for _, r := range p.SeqRanges {
			if r.Begin < 6 || r.End > 15 || r.Num != r.End-r.Begin+1 {
				t.Errorf("ignored visibility boundaries: %v", r)
			}
			if r.ConversationID == "a" {
				return &GeneralWsResp{ErrCode: 10001, ErrMsg: "temporary unavailable"}
			}
		}
		return requestedRecoveryResponse(t, req)
	})
	if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"a": 20, "b": 20}, 1); err == nil {
		t.Fatal("failed conversation reported complete")
	}
	if m.syncedMaxSeqs["a"] != 5 || m.syncedMaxSeqs["b"] != 15 || stored != 10 {
		t.Fatalf("wrong progress: %v stored=%d", m.syncedMaxSeqs, stored)
	}
}

func TestSparsePushDeliversBeforeRecentGapRecovery(t *testing.T) {
	ctx := recoveryContext(t)
	d := &recoveryVersionDB{installed: true}
	m := &MsgSyncer{ctx: ctx, db: d, recvCh: make(chan common.Cmd2Value, 1), syncedMaxSeqs: map[string]int64{"chat": 3}}
	// No transport: the latest message must not wait for any gap request.
	delivered := false
	m.pushTriggerAndSync(ctx, recoveryMsgs("chat", 1003), func(context.Context, map[string]*sdkws.PullMsgs) error {
		delivered = true
		return nil
	})
	if !delivered || !m.messageAlreadyCovered("chat", 1003) {
		t.Fatal("latest push was not delivered and recorded")
	}
	if m.syncedMaxSeqs["chat"] != 3 || m.checkpoints["chat"].Target != 1003 {
		t.Fatal("push consumed gap")
	}
	select {
	case cmd := <-m.recvCh:
		if cmd.Cmd != constant.CmdIMMessageSync {
			t.Fatal("wrong scheduler command")
		}
	default:
		t.Fatal("gap was not scheduled")
	}
}

func TestContiguousMetadataFailureStillRecoversOnSilentPeriodicTick(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	conn.SetConnectionStatus(Connected)
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 3}}
	stored, probes, reconciliations := 0, 0, 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
		if cmd.Cmd == constant.CmdSyncFlag {
			return errors.New("optional profile unavailable")
		}
		stored += len(p.Msgs["chat"].Msgs)
		if p.ReconcileReadSeq {
			reconciliations++
		}
		if !p.Recovery {
			t.Error("recovery lost read-sequence guard")
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.GetNewestSeq {
			probes++
			return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 13}})
		}
		return requestedRecoveryResponse(t, req)
	})
	m.doConnected(ctx)
	if probes != 0 {
		t.Fatal("fixture did not model metadata block")
	}
	m.doMessageSeqReconciliation(ctx)
	if stored != 10 || reconciliations != 1 || m.syncedMaxSeqs["chat"] != 13 {
		t.Fatal("silent retry still waited for next push")
	}
}
