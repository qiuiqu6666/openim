package interaction

import (
	"fmt"
	"sync"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestAllConversationPreviewsPrecedeRecentHistory(t *testing.T) {
	for _, initial := range []bool{false, true} {
		t.Run(fmt.Sprint("initial=", initial), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, db: &recoveryVersionDB{installed: !initial}, reinstalled: initial,
				longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			targets := map[string]int64{"si_peer": 1000, "si_other": 1000}
			for n := 0; n < 205; n++ {
				targets[fmt.Sprintf("sg_%03d", n)] = 1000
			}
			var mu sync.Mutex
			visible := make(map[string]bool)
			stored := make(map[string]map[int64]bool)
			previewRequests, historyRequests := 0, 0
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				var packets map[string]*sdkws.PullMsgs
				if initial {
					packets = cmd.Value.(sdk_struct.CmdMsgSyncInReinstall).Msgs
				} else {
					packets = cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs
				}
				mu.Lock()
				defer mu.Unlock()
				for id, packet := range packets {
					if stored[id] == nil {
						stored[id] = make(map[int64]bool)
					}
					for _, row := range packet.Msgs {
						if stored[id][row.Seq] {
							t.Errorf("duplicate recovery of %s/%d", id, row.Seq)
						}
						stored[id][row.Seq] = true
						if row.Seq == 1000 {
							visible[id] = true
						}
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				pull := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
					panic(err)
				}
				resp := &sdkws.PullMessageBySeqsResp{Msgs: make(map[string]*sdkws.PullMsgs)}
				preview := true
				for _, r := range pull.SeqRanges {
					preview = preview && r.Begin == 1000 && r.End == 1000 && r.Num == 1
				}
				mu.Lock()
				if preview {
					previewRequests++
					if len(pull.SeqRanges) > 100 {
						t.Error("unbounded preview batch")
					}
					if previewRequests == 1 {
						foundSingle, foundGroup := false, false
						for _, r := range pull.SeqRanges {
							foundSingle = foundSingle || r.ConversationID == "si_peer" || r.ConversationID == "si_other"
							foundGroup = foundGroup || r.ConversationID == "sg_000"
						}
						if !foundSingle || !foundGroup {
							t.Error("first preview batch delayed one conversation type")
						}
					}
				} else {
					historyRequests++
					if len(visible) != len(targets) {
						t.Errorf("history started with only %d/%d visible conversations", len(visible), len(targets))
					}
				}
				mu.Unlock()
				for _, r := range pull.SeqRanges {
					if r.Begin < 901 || r.End > 1000 || r.Num != r.End-r.Begin+1 {
						t.Errorf("unbounded recent range: %v", r)
					}
					var seqs []int64
					for seq := r.Begin; seq <= r.End; seq++ {
						seqs = append(seqs, seq)
					}
					resp.Msgs[r.ConversationID] = recoveryMsgs(r.ConversationID, seqs...)[r.ConversationID]
				}
				return wireResponse(resp)
			})
			if err := m.compareSeqsAndBatchSync(ctx, targets, 1); err != nil {
				t.Fatal(err)
			}
			wantHistory := (len(targets)*(recentMessageWindow-1) + SplitPullMsgNum - 1) / SplitPullMsgNum
			if previewRequests != 3 || historyRequests != wantHistory {
				t.Fatalf("preview/history requests: %d/%d", previewRequests, historyRequests)
			}
			for id := range targets {
				if len(stored[id]) != 100 || m.syncedMaxSeqs[id] != 0 || !m.messageAlreadyCovered(id, 1000) {
					t.Fatalf("wrong recovered coverage for %s: %+v", id, m.checkpoints[id])
				}
			}
		})
	}
}

// A server fixture returns exactly the requested sequences for every chat.
func requestedRecoveryResponse(t *testing.T, req Message) *GeneralWsResp {
	t.Helper()
	pull := &sdkws.PullMessageBySeqsReq{}
	if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
		panic(err)
	}
	resp := &sdkws.PullMessageBySeqsResp{Msgs: make(map[string]*sdkws.PullMsgs), NotificationMsgs: make(map[string]*sdkws.PullMsgs)}
	for _, r := range pull.SeqRanges {
		var seqs []int64
		for seq := r.Begin; seq <= r.End; seq++ {
			seqs = append(seqs, seq)
		}
		packet := recoveryMsgs(r.ConversationID, seqs...)[r.ConversationID]
		if IsNotification(r.ConversationID) {
			resp.NotificationMsgs[r.ConversationID] = packet
		} else {
			resp.Msgs[r.ConversationID] = packet
		}
	}
	return wireResponse(resp)
}

func TestLatestPreviewHistoryFailureRetainsGapsForRestart(t *testing.T) {
	ctx := recoveryContext(t)
	d := &recoveryVersionDB{installed: true}
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, db: d, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"si_peer": 100}}
	stopHistory := fmt.Errorf("history unavailable")
	receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		pull := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
			panic(err)
		}
		r := pull.SeqRanges[0]
		if r.Begin == 1000 && r.End == 1000 {
			return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("si_peer", 1000)})
		}
		return &GeneralWsResp{ErrCode: 10001, ErrMsg: stopHistory.Error()}
	})
	if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"si_peer": 1000}, 1); err == nil {
		t.Fatal("failed history reported complete")
	}
	restarted := &MsgSyncer{db: d, syncedMaxSeqs: map[string]int64{"si_peer": 1000}}
	if err := restarted.loadMessageCheckpoints(ctx, []string{"si_peer"}); err != nil {
		t.Fatal(err)
	}
	if restarted.syncedMaxSeqs["si_peer"] != 100 || !restarted.messageAlreadyCovered("si_peer", 1000) {
		t.Fatal("latest preview falsely completed old gaps")
	}
	missing := restarted.recentMissingRanges("si_peer", [2]int64{101, 1000})
	if len(missing) != 1 || missing[0] != [2]int64{901, 999} {
		t.Fatalf("restart lost recent history: %v", missing)
	}
}

func TestDeletedTailRestoresLastValidPreviewBeforeHistory(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, db: &recoveryVersionDB{installed: true}, longConnMgr: conn,
		conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"si_peer": 950}}
	var visible bool
	validReads := 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		for _, packet := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
			for _, row := range packet.Msgs {
				if row.Seq == 100 && row.Status != constant.MsgStatusHasDeleted {
					visible = true
				}
			}
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.PullConvLastMessage {
			validReads++
			return wireResponse(&msg.GetLastMessageResp{Msgs: map[string]*sdkws.MsgData{"si_peer": {Seq: 100, Status: constant.MsgStatusSendSuccess}}})
		}
		pull := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
			panic(err)
		}
		resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}}
		for _, r := range pull.SeqRanges {
			if r.Begin < r.End && !visible {
				t.Error("history preceded last valid preview")
			}
			packet := &sdkws.PullMsgs{}
			for seq := r.Begin; seq <= r.End; seq++ {
				packet.Msgs = append(packet.Msgs, &sdkws.MsgData{Seq: seq, Status: constant.MsgStatusHasDeleted})
			}
			resp.Msgs[r.ConversationID] = packet
		}
		return wireResponse(resp)
	})
	if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"si_peer": 1000}, 1); err != nil {
		t.Fatal(err)
	}
	if !visible || validReads != 1 || m.syncedMaxSeqs["si_peer"] != 1000 {
		t.Fatal("deleted tail hid the remaining valid conversation")
	}
}

func TestFailedLatestPreviewDoesNotHideOtherConversations(t *testing.T) {
	for _, failure := range []string{"transport", "missing", "storage"} {
		t.Run(failure, func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			goodRows := 0
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				packets := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs
				if packets["si_bad"] != nil && failure == "storage" {
					return fmt.Errorf("bad message cannot be saved")
				}
				if packets["sg_good"] != nil {
					goodRows += len(packets["sg_good"].Msgs)
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				pull := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
					panic(err)
				}
				resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}}
				for _, r := range pull.SeqRanges {
					if r.ConversationID == "si_bad" {
						if failure == "transport" {
							return &GeneralWsResp{ErrCode: 10001, ErrMsg: "bad conversation unavailable"}
						}
						if failure == "missing" {
							continue
						}
					}
					var seqs []int64
					for seq := r.Begin; seq <= r.End; seq++ {
						seqs = append(seqs, seq)
					}
					resp.Msgs[r.ConversationID] = recoveryMsgs(r.ConversationID, seqs...)[r.ConversationID]
				}
				return wireResponse(resp)
			})
			if err := m.compareSeqsAndBatchSync(ctx, map[string]int64{"si_bad": 1000, "sg_good": 1000}, 1); err == nil {
				t.Fatal("failed preview reported complete")
			}
			if goodRows != 100 || !m.messageAlreadyCovered("sg_good", 1000) || m.messageAlreadyCovered("si_bad", 1000) || m.checkpoints["si_bad"].Target != 1000 {
				t.Fatalf("failure lost isolation/targets: rows=%d states=%+v", goodRows, m.checkpoints)
			}
		})
	}
}
