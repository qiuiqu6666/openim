package interaction

import (
	"context"
	"fmt"

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

// Keep the SDK's latest-tail policy, but advance each kind only after storage.
func (m *MsgSyncer) commitPulledMessages(ctx context.Context, resp *sdkws.PullMessageBySeqsResp, ranges map[string][2]int64, reinstallTotal int) error {
	if resp == nil {
		return fmt.Errorf("message pull returned no response")
	}
	if err := validatePulledConversationCoverage(resp.Msgs, ranges, false); err != nil {
		return err
	}
	var err error
	if reinstallTotal > 0 {
		err = m.triggerReinstallConversation(ctx, resp.Msgs, reinstallTotal)
	} else {
		err = m.triggerConversation(ctx, resp.Msgs)
	}
	if err != nil {
		return err
	}
	for id, seqs := range ranges {
		if !IsNotification(id) {
			m.syncedMaxSeqs[id] = seqs[1]
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

func validatePulledConversationCoverage(messages map[string]*sdkws.PullMsgs, ranges map[string][2]int64, notification bool) error {
	for id := range ranges {
		if IsNotification(id) != notification {
			continue
		}
		// An explicit empty conversation can represent deleted/expired rows.
		// An omitted conversation says nothing about its requested range and
		// must not permanently advance the cursor past missing messages.
		if messages[id] == nil {
			return fmt.Errorf("message pull response missing requested conversation %q", id)
		}
	}
	return nil
}
