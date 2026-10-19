package interaction

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/sdkws"
)

func TestPullMissingConversationDoesNotAdvanceAndCanRetry(t *testing.T) {
	for _, kind := range []string{"normal", "notification"} {
		t.Run(kind, func(t *testing.T) {
			ctx := recoveryContext(t)
			m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value),
				syncedMaxSeqs: map[string]int64{"chat": 998, "n_chat": 998}}
			receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
			ranges := map[string][2]int64{"chat": {999, 1000}, "n_chat": {999, 1000}}
			resp := &sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", 999, 1000),
				NotificationMsgs: recoveryMsgs("n_chat", 999, 1000)}
			missingID := "chat"
			if kind == "normal" {
				resp.Msgs = nil
			} else {
				missingID = "n_chat"
				resp.NotificationMsgs = nil
			}
			if err := m.commitPulledMessages(ctx, resp, ranges, 0); err == nil {
				t.Fatal("omitted requested conversation accepted as complete")
			}
			if m.syncedMaxSeqs[missingID] != 998 {
				t.Fatal("missing response advanced the cursor")
			}
			if kind == "notification" && m.syncedMaxSeqs["chat"] != 1000 {
				t.Fatal("successfully persisted normal range was not committed")
			}
			resp.Msgs = recoveryMsgs("chat", 999, 1000)
			resp.NotificationMsgs = recoveryMsgs("n_chat", 999, 1000)
			if err := m.commitPulledMessages(ctx, resp, ranges, 0); err != nil {
				t.Fatal(err)
			}
			if m.syncedMaxSeqs["chat"] != 1000 || m.syncedMaxSeqs["n_chat"] != 1000 {
				t.Fatal("complete retry did not commit")
			}
		})
	}
}

func TestPullExplicitDeletedSequencePlaceholdersCanCommit(t *testing.T) {
	m := &MsgSyncer{conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"chat": 998, "n_chat": 998}}
	receiptWorker(t, m.conversationCh, func(common.Cmd2Value) error { return nil })
	resp := &sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", 999, 1000),
		NotificationMsgs: recoveryMsgs("n_chat", 999, 1000)}
	for _, p := range []*sdkws.PullMsgs{resp.Msgs["chat"], resp.NotificationMsgs["n_chat"]} {
		for _, m := range p.Msgs {
			m.Status = constant.MsgStatusHasDeleted
		}
	}
	if err := m.commitPulledMessages(recoveryContext(t), resp,
		map[string][2]int64{"chat": {999, 1000}, "n_chat": {999, 1000}}, 0); err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["chat"] != 1000 || m.syncedMaxSeqs["n_chat"] != 1000 {
		t.Fatal("explicit empty range could not complete")
	}
}

func TestPullAbsentOrNilConversationCannotCommit(t *testing.T) {
	for _, resp := range []*sdkws.PullMessageBySeqsResp{nil, {}, {Msgs: map[string]*sdkws.PullMsgs{"chat": nil}}} {
		m := &MsgSyncer{syncedMaxSeqs: map[string]int64{"chat": 998}}
		if err := m.commitPulledMessages(context.Background(), resp, map[string][2]int64{"chat": {999, 1000}}, 0); err == nil {
			t.Fatal("absent response accepted")
		}
		if m.syncedMaxSeqs["chat"] != 998 {
			t.Fatal("absent response changed cursor")
		}
	}
}
