package interaction

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

// Exercise the real push/gap/receipt chain instead of replacing the sequence
// owner with a callback. The fake server owns every requested sequence; a
// missing received message therefore cannot be explained by retention policy.
func TestLossMatrixPushOrderAndDuplicates(t *testing.T) {
	packets := [][][]int64{
		{{999}, {1000}},
		{{1000}, {999}},
		{{999, 1000}, {999, 1000}},
		{{1000, 999}, {1000}},
		{{999, 999, 1000}},
		{{998, 999}, {998, 999, 1000}},
		{{998}, {997}, {1000}, {999}},
	}
	for _, id := range []string{"chat", "n_chat"} {
		for _, packet := range packets {
			t.Run(fmt.Sprintf("%s/%v", id, packet), func(t *testing.T) {
				ctx := recoveryContext(t)
				conn := &LongConnMgr{send: make(chan Message, 1)}
				m := &MsgSyncer{ctx: ctx, longConnMgr: conn,
					conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{id: 998}}
				var delivered []int64
				var mu sync.Mutex
				receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
					if cmd.Cmd != constant.CmdNewMsgCome && cmd.Cmd != constant.CmdNotification {
						return fmt.Errorf("unexpected failure notification: %s", cmd.Cmd)
					}
					mu.Lock()
					defer mu.Unlock()
					for _, msg := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs[id].Msgs {
						delivered = append(delivered, msg.Seq)
					}
					return nil
				})
				requestWorker(t, conn, func(req Message) *GeneralWsResp {
					pull := &sdkws.PullMessageBySeqsReq{}
					if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
						panic(err)
					}
					resp := &sdkws.PullMessageBySeqsResp{}
					for _, seqRange := range pull.SeqRanges {
						var seqs []int64
						for seq := seqRange.Begin; seq <= seqRange.End; seq++ {
							seqs = append(seqs, seq)
						}
						if IsNotification(id) {
							resp.NotificationMsgs = recoveryMsgs(id, seqs...)
						} else {
							resp.Msgs = recoveryMsgs(id, seqs...)
						}
					}
					return wireResponse(resp)
				})
				for _, seqs := range packet {
					push := &sdkws.PushMessages{}
					if IsNotification(id) {
						push.NotificationMsgs = recoveryMsgs(id, seqs...)
					} else {
						push.Msgs = recoveryMsgs(id, seqs...)
					}
					m.doPushMsg(ctx, push)
				}
				mu.Lock()
				defer mu.Unlock()
				if !reflect.DeepEqual(delivered, []int64{999, 1000}) {
					t.Fatalf("lost or replayed stored messages: %v", delivered)
				}
				if m.syncedMaxSeqs[id] != 1000 {
					t.Fatalf("unexpected committed position: %d", m.syncedMaxSeqs[id])
				}
			})
		}
	}
}

func TestLossMatrixCancelledStorageReceiptKeepsRangeRetryable(t *testing.T) {
	for _, id := range []string{"chat", "n_chat"} {
		t.Run(id, func(t *testing.T) {
			session := recoveryContext(t)
			ctx, cancel := context.WithCancel(session)
			defer cancel()
			m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{id: 998}}
			resp := &sdkws.PullMessageBySeqsResp{}
			if IsNotification(id) {
				resp.NotificationMsgs = recoveryMsgs(id, 999, 1000)
			} else {
				resp.Msgs = recoveryMsgs(id, 999, 1000)
			}
			ranges := map[string][2]int64{id: {999, 1000}}
			done := make(chan error, 1)
			go func() { done <- m.commitPulledMessages(ctx, resp, ranges, 0) }()
			cmd := <-m.conversationCh
			cancel()
			if err := <-done; !errors.Is(err, context.Canceled) {
				t.Fatalf("lost interrupted storage error: %v", err)
			}
			// A storage worker may finish after cancellation. A late receipt must
			// neither block that worker nor independently advance the old owner.
			cmd.Receipt <- nil
			if m.syncedMaxSeqs[id] != 998 {
				t.Fatalf("late receipt consumed unconfirmed range: %v", m.syncedMaxSeqs)
			}
			receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
			if err := m.commitPulledMessages(session, resp, ranges, 0); err != nil {
				t.Fatal(err)
			}
			if m.syncedMaxSeqs[id] != 1000 {
				t.Fatal("the next attempt could not commit the interrupted range")
			}
		})
	}
}

func TestLossMatrixMultiConversationStoreFailureRetriesEntireBatch(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"a": 998, "b": 998}}
	resp := &sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("a", 999, 1000)}
	resp.Msgs["b"] = recoveryMsgs("b", 999, 1000)["b"]
	ranges := map[string][2]int64{"a": {999, 1000}, "b": {999, 1000}}
	failed := false
	receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error {
		if !failed {
			failed = true
			return errors.New("second conversation could not be written")
		}
		return nil
	})
	if err := m.commitPulledMessages(ctx, resp, ranges, 0); err == nil {
		t.Fatal("partial storage failed without surfacing an error")
	}
	if m.syncedMaxSeqs["a"] != 998 || m.syncedMaxSeqs["b"] != 998 {
		t.Fatal("batch success was inferred from partial storage")
	}
	if err := m.commitPulledMessages(ctx, resp, ranges, 0); err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["a"] != 1000 || m.syncedMaxSeqs["b"] != 1000 {
		t.Fatal("batch retry did not commit both conversations")
	}
}

func TestLossMatrixLivePushInterruptsPendingStorageAndRecoversGap(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 4)}
	m := &MsgSyncer{ctx: ctx, loginUserID: "self", longConnMgr: conn,
		recvCh: make(chan common.Cmd2Value, 4), conversationCh: make(chan common.Cmd2Value, 4),
		syncedMaxSeqs: map[string]int64{"chat": 998}}
	storageStarted, recovered := make(chan struct{}), make(chan struct{})
	stored := make(map[int64]bool)
	var mu sync.Mutex
	first := true
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd != constant.CmdNewMsgCome {
			return nil
		}
		if first {
			first = false
			close(storageStarted)
			// Do not acknowledge a partially attempted write. A live message
			// should cancel this owner and arrange for the range to be retried.
			<-cmd.Ctx.Done()
			return cmd.Ctx.Err()
		}
		mu.Lock()
		defer mu.Unlock()
		for _, msg := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs["chat"].Msgs {
			stored[msg.Seq] = true
		}
		if stored[999] && stored[1000] && stored[1001] {
			select {
			case <-recovered:
			default:
				close(recovered)
			}
		}
		return nil
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		if req.Message.ReqIdentifier == constant.GetNewestSeq {
			return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 1000}})
		}
		pull := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
			panic(err)
		}
		var seqs []int64
		for seq := pull.SeqRanges[0].Begin; seq <= pull.SeqRanges[0].End; seq++ {
			seqs = append(seqs, seq)
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)})
	})
	done := make(chan struct{})
	go func() { defer close(done); m.DoListener(ctx) }()
	t.Cleanup(func() { cancel(); <-done })
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdWakeUpDataSync}
	select {
	case <-storageStarted:
	case <-ctx.Done():
		t.Fatal("sync never reached pending storage")
	}
	m.recvCh <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg,
		Value: &sdkws.PushMessages{Msgs: recoveryMsgs("chat", 1001)}}
	select {
	case <-recovered:
	case <-time.After(time.Second):
		t.Fatal("live message did not recover the interrupted storage range")
	}
	cancel()
	<-done
	mu.Lock()
	defer mu.Unlock()
	for _, seq := range []int64{999, 1000, 1001} {
		if !stored[seq] {
			t.Fatalf("interrupted sync lost sequence %d", seq)
		}
	}
}

func TestLossMatrixMultiConversationPushFailureAndPeriodicRecovery(t *testing.T) {
	for _, seed := range []int64{7, 31, 101, 9981000} {
		t.Run(fmt.Sprintf("seed_%d", seed), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			conn.SetConnectionStatus(Connected)
			ids := []string{"single", "group", "n_events"}
			m := &MsgSyncer{ctx: ctx, loginUserID: "self", longConnMgr: conn,
				conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			serverMax := map[string]int64{}
			stored, requested := map[string]map[int64]bool{}, map[string]map[int64]bool{}
			for _, id := range ids {
				m.syncedMaxSeqs[id], serverMax[id] = 998, 998
				stored[id], requested[id] = map[int64]bool{}, map[int64]bool{}
			}
			var mu sync.Mutex
			failed := false
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				if cmd.Cmd != constant.CmdNewMsgCome && cmd.Cmd != constant.CmdNotification {
					return nil
				}
				payload := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs
				mu.Lock()
				defer mu.Unlock()
				for id, msgs := range payload {
					for _, msg := range msgs.Msgs {
						// The sync owner is blocked on this receipt, so this also
						// catches advancing any batch before durable acceptance.
						if msg.Seq <= m.syncedMaxSeqs[id] {
							t.Errorf("%s seq %d was acknowledged before storage (cursor %d)", id, msg.Seq, m.syncedMaxSeqs[id])
						}
					}
				}
				if !failed {
					failed = true
					return errors.New("injected one-time write failure")
				}
				for id, msgs := range payload {
					for _, msg := range msgs.Msgs {
						stored[id][msg.Seq] = true
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.GetNewestSeq {
					return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: serverMax})
				}
				pull := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
					panic(err)
				}
				resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}, NotificationMsgs: map[string]*sdkws.PullMsgs{}}
				mu.Lock()
				defer mu.Unlock()
				for _, seqRange := range pull.SeqRanges {
					id := seqRange.ConversationID
					msgs := &sdkws.PullMsgs{}
					for seq := seqRange.Begin; seq <= seqRange.End; seq++ {
						requested[id][seq] = true
						msgs.Msgs = append(msgs.Msgs, &sdkws.MsgData{Seq: seq})
					}
					if IsNotification(id) {
						resp.NotificationMsgs[id] = msgs
					} else {
						resp.Msgs[id] = msgs
					}
				}
				return wireResponse(resp)
			})
			rng := rand.New(rand.NewSource(seed))
			for round := 0; round < 5; round++ {
				type packet struct {
					id   string
					seqs []int64
				}
				var packets []packet
				for _, id := range ids {
					old := serverMax[id]
					serverMax[id] += int64(1 + rng.Intn(4))
					last := serverMax[id]
					// Drop some pushes, duplicate others, and deliberately put
					// a late old packet after a newer server watermark.
					if rng.Intn(3) != 0 {
						packets = append(packets, packet{id, []int64{last}}, packet{id, []int64{old, last, last}})
					}
				}
				rng.Shuffle(len(packets), func(i, j int) { packets[i], packets[j] = packets[j], packets[i] })
				for _, packet := range packets {
					push := &sdkws.PushMessages{}
					if IsNotification(packet.id) {
						push.NotificationMsgs = recoveryMsgs(packet.id, packet.seqs...)
					} else {
						push.Msgs = recoveryMsgs(packet.id, packet.seqs...)
					}
					m.doPushMsg(ctx, push)
				}
				// Two checks ensure recovery even if this was the first store
				// attempt and it was the one intentionally made to fail.
				m.doMessageSeqReconciliation(ctx)
				m.doMessageSeqReconciliation(ctx)
				mu.Lock()
				for _, id := range ids {
					if m.syncedMaxSeqs[id] != serverMax[id] {
						t.Errorf("round %d %s remains at %d instead of %d", round, id, m.syncedMaxSeqs[id], serverMax[id])
					}
					for seq := int64(999); seq <= serverMax[id]; seq++ {
						if !stored[id][seq] {
							t.Errorf("round %d %s lost generated sequence %d", round, id, seq)
						}
					}
					for seq := range requested[id] {
						if !stored[id][seq] {
							t.Errorf("round %d %s lost requested tail sequence %d", round, id, seq)
						}
					}
				}
				mu.Unlock()
			}
			if !failed {
				t.Fatal("write-failure branch was not exercised")
			}
		})
	}
}

func TestLossMatrixTwoOnlineDevicesHotConversationDoesNotHideSilentGap(t *testing.T) {
	ctx := recoveryContext(t)
	serverMax := map[string]int64{"quiet_group": 1000, "busy_single": 700}
	var devices [2]*MsgSyncer
	var stored [2]map[string][]int64
	var mu sync.Mutex
	for index := range devices {
		conn := &LongConnMgr{send: make(chan Message, 1)}
		conn.SetConnectionStatus(Connected)
		groupSeq := int64(1000)
		if index == 1 {
			groupSeq = 998
		}
		m := &MsgSyncer{ctx: ctx, loginUserID: "same-user", longConnMgr: conn,
			conversationCh: make(chan common.Cmd2Value),
			syncedMaxSeqs:  map[string]int64{"quiet_group": groupSeq, "busy_single": 700}}
		devices[index] = m
		stored[index] = map[string][]int64{}
		receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
			if cmd.Cmd != constant.CmdNewMsgCome {
				return fmt.Errorf("unexpected sync lifecycle while online: %s", cmd.Cmd)
			}
			mu.Lock()
			defer mu.Unlock()
			for id, msgs := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
				for _, msg := range msgs.Msgs {
					stored[index][id] = append(stored[index][id], msg.Seq)
				}
			}
			return nil
		})
		requestWorker(t, conn, func(req Message) *GeneralWsResp {
			if req.Message.ReqIdentifier == constant.GetNewestSeq {
				return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: serverMax})
			}
			pull := &sdkws.PullMessageBySeqsReq{}
			if err := proto.Unmarshal(req.Message.Data, pull); err != nil {
				panic(err)
			}
			resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}}
			for _, seqRange := range pull.SeqRanges {
				msgs := &sdkws.PullMsgs{}
				for seq := seqRange.Begin; seq <= seqRange.End; seq++ {
					msgs.Msgs = append(msgs.Msgs, &sdkws.MsgData{Seq: seq})
				}
				resp.Msgs[seqRange.ConversationID] = msgs
			}
			return wireResponse(resp)
		})
	}
	// Both devices are visibly online and successfully receive another chat.
	// None of that traffic creates a sequence gap in the quiet conversation.
	for seq := int64(701); seq <= 706; seq++ {
		serverMax["busy_single"] = seq
		for _, device := range devices {
			device.doPushMsg(ctx, &sdkws.PushMessages{Msgs: recoveryMsgs("busy_single", seq)})
		}
	}
	if devices[1].syncedMaxSeqs["quiet_group"] != 998 {
		t.Fatal("scenario did not retain the isolated missing tail")
	}
	for _, device := range devices {
		device.doMessageSeqReconciliation(ctx)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(stored[0]["quiet_group"]) != 0 {
		t.Fatal("current device replayed an already committed quiet conversation")
	}
	if !reflect.DeepEqual(stored[1]["quiet_group"], []int64{999, 1000}) {
		t.Fatalf("second device still needs a quiet-chat push: %v", stored[1]["quiet_group"])
	}
	for index, device := range devices {
		if device.syncedMaxSeqs["quiet_group"] != 1000 || device.syncedMaxSeqs["busy_single"] != 706 {
			t.Errorf("device %d remains behind: %v", index+1, device.syncedMaxSeqs)
		}
		if !reflect.DeepEqual(stored[index]["busy_single"], []int64{701, 702, 703, 704, 705, 706}) {
			t.Errorf("device %d duplicated/lost online traffic: %v", index+1, stored[index]["busy_single"])
		}
	}
}
