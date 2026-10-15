package interaction

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

type priorityDB struct {
	*recoveryVersionDB
	conversations []*model_struct.LocalConversation
	rows          map[int64]*model_struct.LocalChatLog
	readErr       error
}

func (d *priorityDB) GetAllConversationListDB(context.Context) ([]*model_struct.LocalConversation, error) {
	return d.conversations, d.readErr
}
func (d *priorityDB) GetMessagesBySeqs(_ context.Context, _ string, seqs []int64) ([]*model_struct.LocalChatLog, error) {
	var rows []*model_struct.LocalChatLog
	for _, s := range seqs {
		if row := d.rows[s]; row != nil {
			rows = append(rows, row)
		}
	}
	return rows, d.readErr
}

func TestHistoryPriorityActivePinnedRecentAndCancellation(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{}
	m := &MsgSyncer{longConnMgr: conn, db: &priorityDB{conversations: []*model_struct.LocalConversation{
		{ConversationID: "pinned", IsPinned: true, LatestMsgSendTime: 1},
		{ConversationID: "recent", LatestMsgSendTime: 50},
		{ConversationID: "old", LatestMsgSendTime: 2},
	}}}
	priorities := m.conversationPriorities(ctx)
	release, err := conn.LockMessageHistory(ctx, "opened", true)
	if err != nil {
		t.Fatal(err)
	}
	ids := []string{"old", "recent", "pinned", "opened"}
	m.prioritizeConversations(ids, priorities)
	if !reflect.DeepEqual(ids, []string{"opened", "pinned", "recent", "old"}) {
		t.Fatal(ids)
	}
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err = conn.LockMessageHistory(cancelled, "opened", true); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	release()
	release()
	if len(conn.historyPriority.lanes) != 0 {
		t.Fatal("lane/foreground interest leaked")
	}
	m.prioritizeConversations(ids, priorities)
	if ids[0] != "pinned" {
		t.Fatal(ids)
	}
}

func TestRecentRecoveryWaitsForForegroundAndDownloadsOnlyMissingRows(t *testing.T) {
	for _, cleared := range []bool{false, true} {
		t.Run(fmt.Sprint("cleared=", cleared), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			d := &priorityDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, rows: make(map[int64]*model_struct.LocalChatLog)}
			m := &MsgSyncer{ctx: ctx, longConnMgr: conn, db: d, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
			var downloaded []int64
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				p := &sdkws.PullMessageBySeqsReq{}
				if err := proto.Unmarshal(req.Message.Data, p); err != nil {
					panic(err)
				}
				resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}}
				for _, r := range p.SeqRanges {
					var seqs []int64
					for s := r.Begin; s <= r.End; s++ {
						seqs = append(seqs, s)
						downloaded = append(downloaded, s)
					}
					resp.Msgs[r.ConversationID] = recoveryMsgs(r.ConversationID, seqs...)[r.ConversationID]
				}
				return wireResponse(resp)
			})
			release, err := conn.LockMessageHistory(ctx, "chat", true)
			if err != nil {
				t.Fatal(err)
			}
			done := make(chan error, 1)
			go func() { done <- m.syncPrioritizedPage(ctx, "chat", [2]int64{201, 300}, 0) }()
			select {
			case err := <-done:
				t.Fatalf("recovery bypassed foreground storage: %v", err)
			case <-time.After(10 * time.Millisecond):
			}
			var stored []int64
			for s := int64(261); s <= 300; s++ {
				stored = append(stored, s)
				if !cleared {
					d.rows[s] = &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(s), Seq: s, SendTime: s, ContentType: constant.Text, Content: `{"content":"local"}`, Status: constant.MsgStatusSendSuccess}
				}
			}
			conn.RememberHistoryRows("chat", stored)
			release()
			if err := <-done; err != nil {
				t.Fatal(err)
			}
			want := 60
			if cleared {
				want = 100
			}
			if len(downloaded) != want {
				t.Fatalf("downloaded %d want %d: %v", len(downloaded), want, downloaded)
			}
			if m.syncedMaxSeqs["chat"] != 0 {
				t.Fatal("recent cache falsely consumed old gap")
			}
			if !m.messageAlreadyCovered("chat", 300) {
				t.Fatal("tail missing")
			}
		})
	}
}

func TestRecoveryPriorityOrdersRealHistoryRequests(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	d := &priorityDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, conversations: []*model_struct.LocalConversation{
		{ConversationID: "z_pin", IsPinned: true, LatestMsgSendTime: 1},
		{ConversationID: "y_recent", LatestMsgSendTime: 99},
		{ConversationID: "a_old", LatestMsgSendTime: 2},
	}}
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, db: d, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
	receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
	var history []string
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}}
		for _, r := range p.SeqRanges {
			if r.Begin != r.End {
				history = append(history, r.ConversationID)
			}
			var seqs []int64
			for s := r.Begin; s <= r.End; s++ {
				seqs = append(seqs, s)
			}
			resp.Msgs[r.ConversationID] = recoveryMsgs(r.ConversationID, seqs...)[r.ConversationID]
		}
		return wireResponse(resp)
	})
	if err := m.syncCompleteMessageRanges(ctx, map[string][2]int64{"a_old": {1, 10}, "y_recent": {1, 10}, "z_pin": {1, 10}}, false); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(history, []string{"z_pin", "y_recent", "a_old"}) {
		t.Fatal(history)
	}
}

func TestHistoryCoordinationIsBoundedAndSessionIsolated(t *testing.T) {
	first, second := &LongConnMgr{}, &LongConnMgr{}
	for n := 0; n < 150; n++ {
		var seqs []int64
		for s := int64(1); s <= 200; s++ {
			seqs = append(seqs, s)
		}
		first.RememberHistoryRows(fmt.Sprint(n), seqs)
	}
	if len(first.historyPriority.covered) != 128 || len(first.historyPriority.covered["149"]) != 100 {
		t.Fatal("unbounded coverage")
	}
	if len(second.storedHistoryRanges("149", [2]int64{1, 200})) != 0 {
		t.Fatal("cross-session coverage")
	}
}

func TestForegroundPreviewAdoptionRequiresReceiptAndRetriesWithoutDownload(t *testing.T) {
	ctx, cancel := context.WithTimeout(recoveryContext(t), time.Second)
	defer cancel()
	conn := &LongConnMgr{send: make(chan Message, 1)}
	d := &priorityDB{recoveryVersionDB: &recoveryVersionDB{}, rows: map[int64]*model_struct.LocalChatLog{
		100: {ClientMsgID: "m100", Seq: 100, ContentType: constant.Text, Content: `{"content":"kept"}`, Status: constant.MsgStatusSendSuccess},
	}}
	conn.RememberHistoryRows("chat", []int64{100})
	m := &MsgSyncer{ctx: ctx, longConnMgr: conn, db: d, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
	var fail atomic.Bool
	fail.Store(true)
	receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error {
		if fail.Load() {
			return errors.New("storage failed")
		}
		return nil
	})
	run := func() error {
		return m.syncLatestMessageBatch(ctx, map[string][2]int64{"chat": {100, 100}}, map[string][2]int64{"chat": {1, 100}}, 1, map[string]error{})
	}
	if err := run(); err == nil {
		t.Fatal("failed receipt accepted")
	}
	if m.messageAlreadyCovered("chat", 100) {
		t.Fatal("failed receipt consumed coverage")
	}
	fail.Store(false)
	if err := run(); err != nil {
		t.Fatal(err)
	}
	if len(conn.send) != 0 {
		t.Fatal("already stored latest preview downloaded twice")
	}
	if !m.messageAlreadyCovered("chat", 100) {
		t.Fatal("retry lost preview")
	}
	if len(conn.historyPriority.lanes) != 0 {
		t.Fatal("failed/retried preview leaked lane")
	}
}
