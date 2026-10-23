package interaction

import (
	"context"
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"sync/atomic"
	"testing"
)

type idleRecoveryDB struct {
	recoveryVersionDB
	boundsReads int
}

func (d *idleRecoveryDB) GetMessageRecoveryBounds(context.Context) ([]*model_struct.LocalConversation, error) {
	d.boundsReads++
	return nil, nil
}
func idleRecoveryFixture(t *testing.T, count int) (*MsgSyncer, *idleRecoveryDB, map[string]int64, context.Context, *atomic.Int64) {
	t.Helper()
	ctx, cancel := context.WithCancel(recoveryContext(t))
	t.Cleanup(cancel)
	d := &idleRecoveryDB{}
	m := &MsgSyncer{ctx: ctx, db: d, syncedMaxSeqs: map[string]int64{}, checkpoints: map[string]messageCheckpoint{}, checkpointIDs: map[string]bool{}}
	targets := map[string]int64{}
	for n := 0; n < count; n++ {
		id := fmt.Sprintf("sg_%03d", n)
		targets[id] = 1000
		m.checkpointIDs[id] = true
		m.checkpoints[id] = messageCheckpoint{Target: 1000, Covered: [][2]int64{{901, 1000}}, persisted: true}
	}
	owner := &messagePageCoordinator{turns: make(chan chan struct{})}
	yields := &atomic.Int64{}
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			select {
			case resume := <-owner.turns:
				yields.Add(1)
				close(resume)
			case <-ctx.Done():
				return
			}
		}
	}()
	t.Cleanup(func() { cancel(); <-done })
	return m, d, targets, context.WithValue(ctx, messagePageContextKey{}, owner), yields
}
func TestIdleCoveredWindowsAvoidBoundsScanAndPageYields(t *testing.T) {
	m, d, targets, ctx, yields := idleRecoveryFixture(t, 332)
	for n := 0; n < 3; n++ {
		if err := m.compareSeqsAndBatchSync(ctx, targets, 10); err != nil {
			t.Fatal(err)
		}
	}
	if d.boundsReads != 0 || yields.Load() != 0 {
		t.Fatalf("idle scans=%d page yields=%d", d.boundsReads, yields.Load())
	}
	for id, state := range m.checkpoints {
		if state.Completed != 0 || m.syncedMaxSeqs[id] != 0 || state.Target != 1000 {
			t.Fatal("idle fast path acknowledged historical gaps")
		}
	}
}
func TestIdleFastPathPreservesUnreadReconciliation(t *testing.T) {
	m, _, targets, ctx, _ := idleRecoveryFixture(t, 332)
	m.conversationCh = make(chan common.Cmd2Value)
	m.pendingReadReconcile = true
	calls := 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		calls++
		if cmd.Cmd != constant.CmdNewMsgCome {
			t.Error("wrong command")
		}
		return nil
	})
	if err := m.compareSeqsAndBatchSync(ctx, targets, 10); err != nil {
		t.Fatal(err)
	}
	if calls != 1 || m.pendingReadReconcile {
		t.Fatalf("read reconciliation lost: calls=%d pending=%v", calls, m.pendingReadReconcile)
	}
}
func TestCoveredWindowStillRecoversNewTail(t *testing.T) {
	m, d, targets, ctx, _ := idleRecoveryFixture(t, 332)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m.longConnMgr = conn
	m.conversationCh = make(chan common.Cmd2Value)
	stored, pulls := 0, 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error { stored++; return nil })
	requestWorker(t, conn, func(req Message) *GeneralWsResp { pulls++; return requestedRecoveryResponse(t, req) })
	targets["sg_000"] = 1001
	if err := m.compareSeqsAndBatchSync(ctx, targets, 10); err != nil {
		t.Fatal(err)
	}
	if pulls != 1 || stored == 0 || d.boundsReads != 3 || !m.messageAlreadyCovered("sg_000", 1001) {
		t.Fatalf("lost new tail: pulls=%d stored=%d scans=%d", pulls, stored, d.boundsReads)
	}
}

func TestIdlePruningKeepsNotificationsAndUncommittedCoverage(t *testing.T) {
	m, _, _, _, _ := idleRecoveryFixture(t, 1)
	m.checkpoints["n_group"] = m.checkpoints["sg_000"]
	uncommitted := m.checkpoints["sg_000"]
	uncommitted.persisted = false
	m.checkpoints["sg_pending"] = uncommitted
	ranges := map[string][2]int64{"sg_000": {1, 1000}, "n_group": {1, 1000}, "sg_pending": {1, 1000}, "sg_new": {1, 1000}}
	pending := m.pendingRecentRecoveryRanges(ranges)
	if len(pending) != 3 {
		t.Fatalf("lost obligations: %v", pending)
	}
	for _, id := range []string{"n_group", "sg_pending", "sg_new"} {
		if _, ok := pending[id]; !ok {
			t.Fatal("skipped", id)
		}
	}
	if len(ranges) != 4 {
		t.Fatal("mutated caller ranges")
	}
}

func BenchmarkIdleCoveredWindows(b *testing.B) {
	ctx := context.Background()
	m := &MsgSyncer{ctx: ctx, db: &idleRecoveryDB{}, syncedMaxSeqs: map[string]int64{}, checkpoints: map[string]messageCheckpoint{}, checkpointIDs: map[string]bool{}}
	targets := map[string]int64{}
	for n := 0; n < 332; n++ {
		id := fmt.Sprintf("sg_%03d", n)
		targets[id] = 1000
		m.checkpointIDs[id] = true
		m.checkpoints[id] = messageCheckpoint{Target: 1000, Covered: [][2]int64{{901, 1000}}, persisted: true}
	}
	b.ReportAllocs()
	b.ResetTimer()
	for n := 0; n < b.N; n++ {
		if err := m.compareSeqsAndBatchSync(ctx, targets, 10); err != nil {
			b.Fatal(err)
		}
	}
}
