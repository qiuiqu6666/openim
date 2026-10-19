//go:build !js

package db

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"gorm.io/gorm"
)

// Messages and their derived conversation/unread state must survive or roll
// back together. The syncer journal is committed afterwards, so a crash between
// this transaction and its receipt safely replays the same page.
func (d *DataBase) CommitMessageSyncBatch(ctx context.Context, updates, inserts map[string][]*model_struct.LocalChatLog, changed, added []*model_struct.LocalConversation) error {
	ids := make([]string, 0, len(inserts)+len(updates))
	for id := range inserts {
		ids = append(ids, id)
	}
	for id := range updates {
		ids = append(ids, id)
	}
	if err := d.initChatLogs(ctx, ids); err != nil {
		return err
	}

	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	return d.conn.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// A transaction-scoped adapter has its own mutex. It never changes the
		// shared connection, and all existing insert/conflict rules are reused.
		batch := &DataBase{conn: tx, loginUserID: d.loginUserID, dbDir: d.dbDir, tableChecker: d.tableChecker}
		for id, rows := range updates {
			if err := applyMessageReadWatermarks(tx, id, d.loginUserID, rows); err != nil {
				return err
			}
			if err := applyMessageRevocations(tx, id, rows); err != nil {
				return err
			}
			for _, row := range rows {
				// A delete can commit while an overlapping history request is in
				// flight. Re-check under this transaction, not only before it.
				var current model_struct.LocalChatLog
				if err := tx.Table(utils.GetTableName(id)).Where("client_msg_id = ?", row.ClientMsgID).Take(&current).Error; err != nil {
					return err
				}
				if current.Status >= constant.MsgStatusHasDeleted && row.Status < constant.MsgStatusHasDeleted {
					continue
				}
				ack := &model_struct.LocalChatLog{ClientMsgID: row.ClientMsgID, Seq: row.Seq, Status: row.Status, RecvID: row.RecvID, SessionType: row.SessionType, ServerMsgID: row.ServerMsgID, SendTime: row.SendTime}
				if row.ContentType == constant.RevokeNotification {
					ack.ContentType = row.ContentType
					ack.Content = row.Content
				}
				if current.ContentType == constant.RevokeNotification && row.ContentType != constant.RevokeNotification {
					ack.ContentType = current.ContentType
					ack.Content = current.Content
				}
				if row.IsRead {
					ack.IsRead = true
					ack.AttachedInfo = row.AttachedInfo
				}
				if err := batch.UpdateMessage(ctx, id, ack); err != nil {
					return err
				}
			}
		}
		if err := batch.BatchInsertMessageMap(ctx, inserts); err != nil {
			return err
		}
		if err := batch.BatchUpdateConversationList(ctx, changed); err != nil {
			return err
		}
		return batch.BatchInsertConversationList(ctx, added)
	})
}
