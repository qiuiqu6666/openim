//go:build !js

package db

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"gorm.io/gorm"
)

// Messages and their derived conversation/unread state must survive or roll
// back together. The syncer journal is committed afterwards, so a crash between
// this transaction and its receipt safely replays the same page.
func (d *DataBase) CommitMessageSyncBatch(ctx context.Context, updates, inserts map[string][]*model_struct.LocalChatLog, changed, added []*model_struct.LocalConversation) error {
	for id := range inserts {
		if err := d.initChatLog(ctx, id); err != nil {
			return err
		}
	}
	for id := range updates {
		if err := d.initChatLog(ctx, id); err != nil {
			return err
		}
	}
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	return d.conn.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// A transaction-scoped adapter has its own mutex. It never changes the
		// shared connection, and all existing insert/conflict rules are reused.
		batch := &DataBase{conn: tx, loginUserID: d.loginUserID, dbDir: d.dbDir, tableChecker: d.tableChecker}
		for id, rows := range updates {
			for _, row := range rows {
				ack := &model_struct.LocalChatLog{ClientMsgID: row.ClientMsgID, Seq: row.Seq, Status: row.Status, RecvID: row.RecvID, SessionType: row.SessionType, ServerMsgID: row.ServerMsgID, SendTime: row.SendTime}
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
