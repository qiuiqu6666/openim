package conversation_msg

import (
	"context"
	"errors"
	"sort"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

// A bounded display snapshot, never a synchronized page or paging boundary.
// No network, gap repair, cache maintenance or cursor mutation belongs here.
func (c *Conversation) localHistorySnapshot(ctx context.Context, req sdk.GetAdvancedHistoryMessageListParams, reverse bool) (*sdk.GetAdvancedHistoryMessageListCallback, error) {
	if req.ConversationID == "" || reverse || req.StartClientMsgID != "" || req.ScanCursor != nil {
		return nil, errors.New("local snapshot requires an unanchored conversation")
	}
	result := &sdk.GetAdvancedHistoryMessageListCallback{LocalSnapshot: true, MessageList: []*sdk_struct.MsgStruct{}}
	conversation, err := c.db.GetConversation(ctx, req.ConversationID)
	if err != nil {
		return nil, err
	}
	if conversation == nil || conversation.IsPrivateChat {
		return result, nil
	}
	rows, err := c.db.GetMessageList(ctx, req.ConversationID, req.Count, 0, 0, "", false)
	if err != nil {
		return nil, err
	}
	for _, row := range rows {
		if row.Status >= constant.MsgStatusHasDeleted || row.ContentType == constant.Typing ||
			(row.Seq > 0 && row.Seq < conversation.MinSeq) {
			continue
		}
		message := LocalChatLogToMsgStruct(row)
		if message.AttachedInfoElem.IsPrivateChat {
			continue
		}
		result.MessageList = append(result.MessageList, message)
	}
	sort.Sort(sdk_struct.NewMsgList(result.MessageList))
	return result, nil
}
