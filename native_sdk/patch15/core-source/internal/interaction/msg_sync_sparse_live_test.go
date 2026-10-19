package interaction

import (
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
)

func TestCoveredSparseLiveWindowDoesNotEnqueueEmptySync(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{ctx: ctx, conversationCh: make(chan common.Cmd2Value), recvCh: make(chan common.Cmd2Value, 4),
		syncedMaxSeqs: map[string]int64{"chat": 0}, checkpoints: map[string]messageCheckpoint{"chat": {Target: 171, Covered: [][2]int64{{72, 171}}}}}
	receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
	for seq := int64(172); seq <= 180; seq++ {
		m.pushTriggerAndSync(ctx, recoveryMsgs("chat", seq), m.triggerConversation)
	}
	if len(m.recvCh) != 0 || m.pendingReadReconcile || m.syncedMaxSeqs["chat"] != 0 {
		t.Fatal("covered live window triggered global recovery or acknowledged old holes")
	}
	m.pushTriggerAndSync(ctx, recoveryMsgs("chat", 182), m.triggerConversation)
	if len(m.recvCh) != 1 || !m.pendingReadReconcile {
		t.Fatal("a genuine missing sequence did not schedule recovery")
	}
}
