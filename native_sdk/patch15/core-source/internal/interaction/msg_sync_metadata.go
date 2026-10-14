package interaction

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

// Keep metadata failures visible and retryable, but only after offline messages
// have been persisted and published. The existing interruptible conversation
// worker owns this work; no untracked goroutine can outlive the login session.
func (m *MsgSyncer) syncMetadataAfterMessages(ctx context.Context) error {
	return common.SendSyncCmdWithReceipt(ctx, common.Cmd2Value{
		Cmd:   constant.CmdSyncData,
		Value: sdk_struct.CmdNewMsgComeToConversation{},
	}, m.conversationCh)
}
