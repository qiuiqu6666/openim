package interaction

import (
	"context"
	"fmt"
	"sort"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func (m *MsgSyncer) triggerSyncStart(ctx context.Context, flag int) error {
	return common.SendSyncCmdWithReceipt(ctx, common.Cmd2Value{
		Cmd:   constant.CmdSyncFlag,
		Value: sdk_struct.CmdNewMsgComeToConversation{SyncFlag: flag},
	}, m.conversationCh)
}

// A checkpoint is committed only for a fully covered, durably acknowledged page.
func (m *MsgSyncer) commitPulledMessages(ctx context.Context, resp *sdkws.PullMessageBySeqsResp, ranges map[string][2]int64, reinstallTotal int, notifyConversations ...bool) error {
	if resp == nil {
		return fmt.Errorf("message pull returned no response")
	}
	if err := validatePulledConversationCoverage(resp.Msgs, ranges, false); err != nil {
		return err
	}
	for id, r := range ranges {
		if err := m.rememberMessageTarget(ctx, id, r[1]); err != nil {
			return err
		}
		if IsNotification(id) && r[0] > max(1, m.syncedMaxSeqs[id]+1) {
			return fmt.Errorf("non-contiguous checkpoint for %q", id)
		}
	}
	var err error
	for _, rows := range resp.Msgs {
		sort.Slice(rows.Msgs, func(i, j int) bool { return rows.Msgs[i].Seq < rows.Msgs[j].Seq })
	}
	if reinstallTotal > 0 {
		err = m.triggerReinstallConversation(ctx, resp.Msgs, reinstallTotal, notifyConversations...)
	} else {
		if len(resp.Msgs) > 0 {
			err = common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: constant.CmdNewMsgCome,
				Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: resp.Msgs, Recovery: true, ReconcileReadSeq: !m.recoveryReadSeqReady}}, m.conversationCh)
			if err == nil {
				m.recoveryReadSeqReady = true
			}
		}
	}
	if err != nil {
		return err
	}
	for id, seqs := range ranges {
		if !IsNotification(id) {
			if err := m.commitMessageCoverage(ctx, id, [][2]int64{seqs}); err != nil {
				return err
			}
		}
	}
	if err := validatePulledConversationCoverage(resp.NotificationMsgs, ranges, true); err != nil {
		return err
	}
	if err := m.triggerNotification(ctx, resp.NotificationMsgs); err != nil {
		return err
	}
	for id, seqs := range ranges {
		if IsNotification(id) {
			m.syncedMaxSeqs[id] = seqs[1]
		}
	}
	return nil
}

type incompleteMessageRange struct{ id string }

func (e *incompleteMessageRange) Error() string {
	return fmt.Sprintf("incomplete message range for %q", e.id)
}

func validatePulledConversationCoverage(messages map[string]*sdkws.PullMsgs, ranges map[string][2]int64, notification bool) error {
	for id, r := range ranges {
		if IsNotification(id) != notification {
			continue
		}
		if messages[id] == nil {
			return &incompleteMessageRange{id: id}
		}
		seen := make(map[int64]bool, len(messages[id].Msgs))
		for _, row := range messages[id].Msgs {
			if row == nil || row.Seq < max(1, r[0]) || row.Seq > r[1] || seen[row.Seq] {
				return fmt.Errorf("invalid or duplicate sequence in response for %q", id)
			}
			seen[row.Seq] = true
		}
		// Deleted rows with a sequence are explicit evidence. Neither isEnd
		// nor an empty conversation proves that an internal gap is invisible.
		if int64(len(seen)) != r[1]-max(1, r[0])+1 {
			return &incompleteMessageRange{id: id}
		}
	}
	return nil
}
