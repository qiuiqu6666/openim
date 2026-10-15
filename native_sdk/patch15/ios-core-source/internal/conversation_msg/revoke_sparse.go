package conversation_msg

import (
	"context"
	"encoding/json"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type sparseRevocationStore interface {
	SaveMessageRevocation(context.Context, *sdkws.RevokeMsgTips) error
	ApplyMessageRevocations(context.Context, string, []*model_struct.LocalChatLog) error
}

func (c *Conversation) applyStoredRevocations(ctx context.Context, id string, rows []*model_struct.LocalChatLog) error {
	if store, ok := c.db.(sparseReadStore); ok {
		if err := store.ApplyMessageReadWatermarks(ctx, id, rows); err != nil {
			return err
		}
	}
	if store, ok := c.db.(sparseRevocationStore); ok {
		return store.ApplyMessageRevocations(ctx, id, rows)
	}
	return nil
}

func (c *Conversation) applyIncomingRevocations(ctx context.Context, id string, msgs []*sdkws.MsgData) error {
	rows := make([]*model_struct.LocalChatLog, 0, len(msgs))
	for _, msg := range msgs {
		rows = append(rows, MsgDataToLocalChatLog(msg))
	}
	if err := c.applyStoredRevocations(ctx, id, rows); err != nil {
		return err
	}
	for i, row := range rows {
		msgs[i].ContentType = int32(row.ContentType)
		msgs[i].Content = []byte(row.Content)
		msgs[i].IsRead = row.IsRead
		msgs[i].AttachedInfo = row.AttachedInfo
	}
	return nil
}

func (c *Conversation) revokeUncachedPreview(ctx context.Context, tips *sdkws.RevokeMsgTips) error {
	conv, err := c.db.GetConversation(ctx, tips.ConversationID)
	if isLocalRecordMissing(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var latest sdk_struct.MsgStruct
	if conv.LatestMsg == "" {
		return nil
	}
	if err := json.Unmarshal([]byte(conv.LatestMsg), &latest); err != nil {
		return err
	}
	if latest.Seq != tips.Seq {
		return nil
	}
	row := MsgStructToLocalChatLog(&latest)
	if err := c.applyStoredRevocations(ctx, tips.ConversationID, []*model_struct.LocalChatLog{row}); err != nil {
		return err
	}
	var notification sdk_struct.NotificationElem
	if err := json.Unmarshal([]byte(row.Content), &notification); err != nil {
		return err
	}
	latest = *LocalChatLogToMsgStruct(row)
	if err := c.db.UpdateColumnsConversation(ctx, tips.ConversationID, map[string]interface{}{"latest_msg": utils.StructToJsonString(latest)}); err != nil {
		return err
	}
	c.msgListener().OnNewRecvMessageRevoked(notification.Detail)
	c.doUpdateConversation(common.Cmd2Value{Ctx: ctx, Value: common.UpdateConNode{Action: constant.ConChange, Args: []string{tips.ConversationID}}})
	return nil
}
