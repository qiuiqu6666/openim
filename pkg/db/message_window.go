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
		// Count server sequences, not physical rows: old SDKs may have left
		// multiple tombstones for one seq. A row LIMIT would displace other
		// sequences and make a complete window appear permanently incomplete.
		q := tx.Table(table).Select("seq").Where("seq > 0")
		if target > 0 {
			q = q.Where("seq <= ?", target)
		}
		seqs := q.Group("seq").Order("seq DESC").Limit(min(max(count, 1), 300))
		// Keep the stored rows and their deletion/revocation state unchanged.
		// The window builder still checks every required seq; sparse ranges
		// must not become publishable merely because this query returns rows.
		if err := tx.Table(table).Where("seq IN (?)", seqs).Order("seq DESC").Find(&result.Rows).Error; err != nil {
			return err
		}
		// Local call records have no server sequence. Read them in the same
		// transaction; they must not contribute to server coverage.
		var local []*model_struct.LocalChatLog
		localQuery := tx.Table(table).Where("seq = 0")
		if len(result.Rows) > 0 {
			localQuery = localQuery.Where("send_time >= ?", result.Rows[len(result.Rows)-1].SendTime)
		}
		if err := localQuery.Order("send_time DESC, client_msg_id DESC").Limit(300).Find(&local).Error; err != nil {
			return err
		}
		result.Rows = append(result.Rows, local...)
		return applyMessageRevocations(tx, id, result.Rows)
	})
	return result, err
}
