//go:build !js

package db

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"gorm.io/gorm"
)

// ReadMessageWindow reads permissions, rows and durable revocations together.
// A crash cannot leave a published coverage proof ahead of its messages: the
// proof is reconstructed from committed rows on every native snapshot read.
func (d *DataBase) ReadMessageWindow(ctx context.Context, id string, count int, target int64) (*model_struct.MessageWindowRead, error) {
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	result := &model_struct.MessageWindowRead{Conversation: &model_struct.LocalConversation{}}
	err := d.conn.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("conversation_id = ?", id).Take(result.Conversation).Error; err != nil {
			return err
		}
		table := utils.GetTableName(id)
		if !tx.Migrator().HasTable(table) {
			return nil
		}
		q := tx.Table(table).Where("seq > 0")
		if target > 0 {
			q = q.Where("seq <= ?", target)
		}
		if err := q.Order("seq DESC").Limit(min(max(count, 1), 300)).Find(&result.Rows).Error; err != nil {
			return err
		}
		return applyMessageRevocations(tx, id, result.Rows)
	})
	return result, err
}
