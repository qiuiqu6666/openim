//go:build !js

package db

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"gorm.io/gorm"
)

func (d *DataBase) ReconcileGroupConversationProfilePage(ctx context.Context, afterID string, limit int) ([]*model_struct.LocalConversation, error) {
	if limit <= 0 || limit > 128 {
		limit = 128
	}
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	var result []*model_struct.LocalConversation
	err := d.conn.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var changes []struct {
			ConversationID string
			GroupName      string
			FaceURL        string
		}
		// Read just keys and current group profiles. Latest messages can be
		// large; fetch them only for the bounded set actually being published.
		err := tx.Table("local_conversations AS c").
			Select("c.conversation_id, g.name AS group_name, g.face_url").
			Joins("JOIN local_groups AS g ON g.group_id = c.group_id").
			Where("c.latest_msg_send_time > 0 AND c.conversation_type IN ? AND c.conversation_id > ?", []int32{constant.ReadGroupChatType, constant.WriteGroupChatType}, afterID).
			Where("COALESCE(c.show_name, '') <> COALESCE(g.name, '') OR COALESCE(c.face_url, '') <> COALESCE(g.face_url, '')").
			Order("c.conversation_id ASC").Limit(limit).Scan(&changes).Error
		if err != nil || len(changes) == 0 {
			return err
		}
		ids := make([]string, 0, len(changes))
		for _, change := range changes {
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Model(&model_struct.LocalConversation{}).Where("conversation_id = ?", change.ConversationID).
				Updates(map[string]interface{}{"show_name": change.GroupName, "face_url": change.FaceURL}).Error; err != nil {
				return err
			}
			ids = append(ids, change.ConversationID)
		}
		return tx.Where("conversation_id IN ?", ids).Order("conversation_id ASC").Find(&result).Error
	})
	return result, err
}
