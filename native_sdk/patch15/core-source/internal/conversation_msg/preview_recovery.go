package conversation_msg

import (
	"context"
	"encoding/json"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

type selfDeliveryKey struct {
	conversationID string
	clientMsgID    string
}

func selfMessagePreview(conversationID string, msg *sdk_struct.MsgStruct) *model_struct.LocalConversation {
	row := &model_struct.LocalConversation{ConversationID: conversationID,
		ConversationType: msg.SessionType, LatestMsg: utils.StructToJsonString(msg), LatestMsgSendTime: msg.SendTime}
	switch msg.SessionType {
	case constant.SingleChatType:
		row.UserID = msg.RecvID
	case constant.WriteGroupChatType, constant.ReadGroupChatType:
		row.GroupID = msg.GroupID
	}
	return row
}

func (c *Conversation) updateSelfMessagePreview(conversationID string, msg *sdk_struct.MsgStruct, rows map[string]*model_struct.LocalConversation) {
	c.updateConversation(selfMessagePreview(conversationID, msg), rows)
}

func newerConversationPreview(next, old *model_struct.LocalConversation) bool {
	// An acknowledgement repairs its own pending preview even when the
	// server corrects the client's send timestamp backwards. Another pending
	// message must keep its existing precedence.
	var a, b sdk_struct.MsgStruct
	if json.Unmarshal([]byte(next.LatestMsg), &a) != nil || json.Unmarshal([]byte(old.LatestMsg), &b) != nil {
		return next.LatestMsgSendTime > old.LatestMsgSendTime
	}
	// Confirmed messages use the same server order as the chat timeline.
	// Local/pending records retain their existing time-based precedence.
	if a.Seq > 0 && b.Seq > 0 {
		return a.Seq > b.Seq
	}
	if a.ClientMsgID != "" && a.ClientMsgID == b.ClientMsgID && a.Seq > 0 && b.Seq == 0 {
		return true
	}
	return next.LatestMsgSendTime > old.LatestMsgSendTime
}

// Native adapters recheck visibility, deletion and revocation under the same
// transaction as the preview write. Never derive a preview from a network
// response that may have lost a race with a local delete.
func (c *Conversation) reconcileStoredPreviews(ctx context.Context, ids []string) ([]*model_struct.LocalConversation, error) {
	if db, ok := c.db.(interface {
		ReconcileConversationPreviews(context.Context, []string, func(*model_struct.LocalChatLog) string) ([]*model_struct.LocalConversation, error)
	}); ok {
		return db.ReconcileConversationPreviews(ctx, ids, func(row *model_struct.LocalChatLog) string {
			return utils.StructToJsonString(LocalChatLogToMsgStruct(row))
		})
	}
	return c.db.GetMultipleConversationDB(ctx, ids)
}

// Repair only equal-time server messages already on disk. Keep hidden rows,
// unsent messages, timestamps, unread counts and pagination order untouched.
// Caller holds conversationSyncMutex.
func (c *Conversation) repairTiedPreviews(ctx context.Context, rows []*model_struct.LocalConversation) error {
	for _, row := range rows {
		var old sdk_struct.MsgStruct
		if row.LatestMsgSendTime <= 0 || json.Unmarshal([]byte(row.LatestMsg), &old) != nil || old.Seq <= 0 {
			continue
		}
		messages, err := c.db.GetLatestActiveMessage(ctx, row.ConversationID, false)
		if err != nil {
			return err
		}
		if len(messages) == 0 {
			continue
		}
		msg := messages[0]
		if msg.SendTime != row.LatestMsgSendTime || msg.Seq <= old.Seq {
			continue
		}
		converted := LocalChatLogToMsgStruct(msg)
		preview := utils.StructToJsonString(converted)
		if err := c.db.UpdateColumnsConversation(ctx, row.ConversationID, map[string]interface{}{"latest_msg": preview}); err != nil {
			return err
		}
		row.LatestMsg = preview
	}
	return nil
}
