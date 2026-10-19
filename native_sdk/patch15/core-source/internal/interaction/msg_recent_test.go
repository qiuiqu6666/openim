package interaction

import (
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"reflect"
	"testing"
)

func TestSparseRecentCoverageMergesWithoutPromotingOldGap(t *testing.T) {
	ctx := recoveryContext(t)
	d := &recoveryVersionDB{installed: true}
	m := &MsgSyncer{db: d, syncedMaxSeqs: map[string]int64{"chat": 100}}
	if err := m.commitMessageCoverage(ctx, "chat", [][2]int64{{950, 1000}, {901, 960}}); err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["chat"] != 100 || !reflect.DeepEqual(m.checkpoints["chat"].Covered, [][2]int64{{901, 1000}}) {
		t.Fatalf("invalid coverage: %+v", m.checkpoints["chat"])
	}
	restarted := &MsgSyncer{db: d, syncedMaxSeqs: map[string]int64{"chat": 1000}}
	if err := restarted.loadMessageCheckpoints(ctx, []string{"chat"}); err != nil {
		t.Fatal(err)
	}
	if restarted.syncedMaxSeqs["chat"] != 100 {
		t.Fatal("restart trusted highest cached seq")
	}
	if got := restarted.recentMissingRanges("chat", [2]int64{101, 1000}); len(got) != 0 {
		t.Fatal("old gap became automatic work", got)
	}
	if got := restarted.recentMissingRanges("chat", [2]int64{101, 1002}); !reflect.DeepEqual(got, [][2]int64{{1001, 1002}}) {
		t.Fatal(got)
	}
	if err := restarted.commitMessageCoverage(ctx, "chat", [][2]int64{{101, 900}}); err != nil {
		t.Fatal(err)
	}
	if restarted.syncedMaxSeqs["chat"] != 1000 || len(restarted.checkpoints["chat"].Covered) != 0 {
		t.Fatal("adjacent coverage failed to merge")
	}
}

func TestUnreadReconciliationRunsWhenLivePushAlreadyFilledWindow(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{syncedMaxSeqs: map[string]int64{"chat": 100}, conversationCh: make(chan common.Cmd2Value), pendingReadReconcile: true}
	if err := m.commitMessageCoverage(ctx, "chat", [][2]int64{{901, 1000}}); err != nil {
		t.Fatal(err)
	}
	reconciled := false
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
		reconciled = p.ReconcileReadSeq && len(p.Msgs) == 0
		return nil
	})
	if err := m.syncCompleteMessageRanges(ctx, map[string][2]int64{"chat": {101, 1000}}, false); err != nil {
		t.Fatal(err)
	}
	if !reconciled || m.pendingReadReconcile {
		t.Fatal("read watermark not reconciled")
	}
}
