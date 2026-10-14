package conversation_msg

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/log"
)

// Display metadata is not authorization: the server has already accepted the
// recall. A missing profile must never leave the original content visible.
func (c *Conversation) revokeDisplayInfo(ctx context.Context, tips *sdkws.RevokeMsgTips, message *model_struct.LocalChatLog) (int32, string) {
	var fallback string
	if tips.RevokerUserID == message.SendID {
		fallback = message.SenderNickname
	}
	if tips.IsAdminRevoke || tips.SesstionType == constant.SingleChatType {
		_, name, err := c.getUserNameAndFaceURL(ctx, tips.RevokerUserID)
		if err != nil {
			log.ZWarn(ctx, "revoke display profile unavailable", err)
			return 0, fallback
		}
		return 0, name
	}
	if tips.SesstionType == constant.ReadGroupChatType {
		conversation, err := c.db.GetConversation(ctx, tips.ConversationID)
		if err != nil {
			log.ZWarn(ctx, "revoke display conversation unavailable", err)
			return 0, fallback
		}
		members, err := c.group.GetSpecifiedGroupMembersInfo(ctx, conversation.GroupID, []string{tips.RevokerUserID})
		if err != nil {
			log.ZWarn(ctx, "revoke display group member unavailable", err)
			return 0, fallback
		}
		if len(members) > 0 && members[0] != nil {
			return members[0].RoleLevel, members[0].Nickname
		}
	}
	return 0, fallback
}
