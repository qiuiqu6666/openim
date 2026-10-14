package conversation_msg

import (
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

// First-login metadata is a prerequisite for message persistence. Keep the
// listener draining notifications, but do not cancel bootstrap for live work.
func (c *Conversation) ProtectSyncCommand(cmd common.Cmd2Value) bool {
	value, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	return cmd.Cmd == constant.CmdSyncFlag && ok && value.SyncFlag == constant.AppDataSyncStart
}

// Metadata network waits must not hold up sent-message status/conversation
// updates. Keep all message persistence and callback application serialized.
func (c *Conversation) InterruptibleCommand(cmd common.Cmd2Value) bool {
	if cmd.Cmd == constant.CmdSyncData {
		return true
	}
	if cmd.Cmd != constant.CmdSyncFlag {
		return false
	}
	value, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
	return ok && (value.SyncFlag == constant.MsgSyncBegin || value.SyncFlag == constant.AppDataSyncStart)
}
