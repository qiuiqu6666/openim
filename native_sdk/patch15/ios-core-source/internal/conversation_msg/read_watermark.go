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
	"github.com/openimsdk/tools/errs"
)

type readWatermarkStore interface {
	GetReadWatermarkMessages(context.Context, string, int64, int64) ([]*model_struct.LocalChatLog, error)
}

// A cumulative receipt is valid even when no corresponding message is stored
// locally. Only the relevant sender's positive server sequences are marked.
func (c *Conversation) doReadWatermark(ctx context.Context, msg *sdkws.MsgData, tips *sdkws.MarkAsReadTips) error {
	if tips.HasReadSeq <= 0 {
		return nil
	}
	conversation, err := c.db.GetConversation(ctx, tips.ConversationID)
	if err != nil {
		return err
	}
	self := tips.MarkAsReadUserID == c.loginUserID
	if conversation.ConversationType != constant.SingleChatType {
		if self {
			return c.doUnreadCount(ctx, conversation, tips.HasReadSeq, nil)
		}
		return nil
	}
	store, ok := c.db.(readWatermarkStore)
	if !ok {
		return errs.New("cumulative read receipts require native storage").Wrap()
	}
	var latest sdk_struct.MsgStruct
	if conversation.LatestMsg != "" {
		if err = json.Unmarshal([]byte(conversation.LatestMsg), &latest); err != nil {
			return err
		}
	}
	for after := int64(0); ; {
		rows, err := store.GetReadWatermarkMessages(ctx, tips.ConversationID, after, tips.HasReadSeq)
		if err != nil {
			return err
		}
		if len(rows) == 0 {
			break
		}
		previous := after
		var ids []string
		for _, row := range rows {
			if row.Seq > after {
				after = row.Seq
			}
			if row.Seq <= 0 || row.Seq > tips.HasReadSeq || (row.SendID == c.loginUserID) == self {
				continue
			}
			if !row.IsRead {
				var attached sdk_struct.AttachedInfoElem
				_ = utils.JsonStringToStruct(row.AttachedInfo, &attached)
				attached.HasReadTime = msg.SendTime
				row.AttachedInfo = utils.StructToJsonString(attached)
				row.IsRead = true
				if err = c.db.UpdateMessage(ctx, tips.ConversationID, row); err != nil {
					return err
				}
			}
			if !self {
				ids = append(ids, row.ClientMsgID)
			}
		}
		if len(ids) > 0 {
			c.msgListener().OnRecvC2CReadReceipt(utils.StructToJsonString([]*sdk_struct.MessageReceipt{{UserID: tips.MarkAsReadUserID, MsgIDList: ids, SessionType: conversation.ConversationType, ReadTime: msg.SendTime}}))
		}
		if after <= previous {
			return errs.New("read watermark cursor did not advance").Wrap()
		}
	}
	columns := map[string]interface{}{}
	if latest.Seq > 0 && latest.Seq <= tips.HasReadSeq && (latest.SendID == c.loginUserID) != self && !latest.IsRead {
		latest.IsRead = true
		columns["latest_msg"] = utils.StructToJsonString(latest)
	}
	if self {
		maxSeq := c.maxSeqRecorder.Get(tips.ConversationID)
		if maxSeq > 0 {
			unread := maxSeq - tips.HasReadSeq
			if unread < 0 {
				unread = 0
			}
			// A delayed receipt must never resurrect already-cleared unread badges.
			if unread < int64(conversation.UnreadCount) {
				columns["unread_count"] = unread
			}
		}
	}
	if len(columns) > 0 {
		if err = c.db.UpdateColumnsConversation(ctx, tips.ConversationID, columns); err != nil {
			return err
		}
		if err = common.TriggerCmdUpdateConversation(ctx, common.UpdateConNode{ConID: tips.ConversationID, Action: constant.ConChange, Args: []string{tips.ConversationID}}, c.GetCh()); err != nil {
			return err
		}
		if self {
			return common.TriggerCmdUpdateConversation(ctx, common.UpdateConNode{Action: constant.TotalUnreadMessageChanged}, c.GetCh())
		}
	}
	return nil
}
