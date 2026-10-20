//go:build !js

package db

import (
	"context"
	"encoding/json"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"gorm.io/gorm"
)

// ReconcileConversationPreviews atomically advances visible, confirmed previews.
// Only preview fields are written: unread/read watermarks, drafts and settings
// remain owned by their existing flows. Empty/hidden/local/pending previews are
// intentional states and must not be resurrected by history or a list read.
func (d *DataBase) ReconcileConversationPreviews(ctx context.Context, ids []string, encode func(*model_struct.LocalChatLog) string) ([]*model_struct.LocalConversation, error) {
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	var rows []*model_struct.LocalConversation
	err := d.conn.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("conversation_id IN ?", ids).Find(&rows).Error; err != nil {
			return err
		}
		for _, row := range rows {
			var old sdk_struct.MsgStruct
			if row.IsPrivateChat || row.LatestMsgSendTime <= 0 ||
				json.Unmarshal([]byte(row.LatestMsg), &old) != nil || old.Seq <= 0 {
				continue
			}
			table := utils.GetTableName(row.ConversationID)
			if !tx.Migrator().HasTable(table) {
				continue
			}
			// Page past private/control rows without loading an entire history.
			var before int64
			for {
				var candidates []*model_struct.LocalChatLog
				q := tx.Table(table).Where("seq > ? AND seq >= ? AND status < ? AND content_type <> ?",
					old.Seq, row.MinSeq, constant.MsgStatusHasDeleted, constant.Typing)
				if before > 0 {
					q = q.Where("seq < ?", before)
				}
				if err := q.Order("seq DESC").Limit(32).Find(&candidates).Error; err != nil {
					return err
				}
				if len(candidates) == 0 {
					break
				}
				if err := applyMessageRevocations(tx, row.ConversationID, candidates); err != nil {
					return err
				}
				var candidate *model_struct.LocalChatLog
				for _, msg := range candidates {
					var attached sdk_struct.AttachedInfoElem
					if msg.AttachedInfo != "" {
						if json.Unmarshal([]byte(msg.AttachedInfo), &attached) != nil || attached.IsPrivateChat {
							continue
						}
					}
					candidate = msg
					break
				}
				if candidate == nil {
					before = candidates[len(candidates)-1].Seq
					continue
				}
				preview := encode(candidate)
				if err := tx.Model(&model_struct.LocalConversation{}).Where("conversation_id = ?", row.ConversationID).
					Updates(map[string]interface{}{"latest_msg": preview, "latest_msg_send_time": candidate.SendTime}).Error; err != nil {
					return err
				}
				row.LatestMsg, row.LatestMsgSendTime = preview, candidate.SendTime
				break
			}
		}
		return nil
	})
	return rows, err
}
