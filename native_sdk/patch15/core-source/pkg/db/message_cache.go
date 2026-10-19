//go:build !js

package db

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// Limits apply to replaceable, acknowledged server messages. Unsent/failed
// messages, local deletion markers and durable state overlays are not cache.
const MessageCacheConversationLimit = 1000
const MessageCacheAccountLimit = 20000
const MessageCacheByteLimit int64 = 64 << 20

// Adopt existing conversation tables once on upgrade. This only compacts local
// replaceable bodies; it never downloads history or rewrites unread/checkpoints.
func (d *DataBase) initializeMessageCache(ctx context.Context, tables []string) error {
	var known []messageCacheConversation
	if err := d.conn.WithContext(ctx).Find(&known).Error; err != nil {
		return err
	}
	adopted := make(map[string]bool, len(known))
	for _, row := range known {
		adopted[row.ConversationID] = true
	}
	for _, table := range tables {
		if !strings.HasPrefix(table, "chat_logs_") {
			continue
		}
		id := strings.TrimPrefix(table, "chat_logs_")
		if !adopted[id] {
			if err := d.MaintainMessageCache(ctx, id, nil); err != nil {
				return err
			}
		}
	}
	return nil
}

type messageCacheEntry struct {
	ConversationID string `gorm:"primaryKey;index:cache_lru_conversation,priority:1"`
	ClientMsgID    string `gorm:"primaryKey"`
	Seq            int64
	SendTime       int64
	Touched        int64 `gorm:"index:cache_lru;index:cache_lru_conversation,priority:2"`
	Bytes          int64
}

func (messageCacheEntry) TableName() string { return "sdk_message_cache_v1" }

type messageCacheConversation struct {
	ConversationID string `gorm:"primaryKey"`
}

func (messageCacheConversation) TableName() string { return "sdk_message_cache_conversations_v1" }

// A small cursor survives eviction, so an open page can still request the next
// older page by clientMsgID even under sustained live traffic.
type messageCacheAnchor struct {
	ConversationID string `gorm:"primaryKey"`
	ClientMsgID    string `gorm:"primaryKey"`
	Seq            int64
	SendTime       int64
	Touched        int64 `gorm:"index"`
}

func (messageCacheAnchor) TableName() string { return "sdk_message_cache_anchors_v1" }

// Two paging cursors per conversation/view survive arbitrary live traffic.
// They contain no message body and are replaced when that view changes pages.
type messageCacheCursor struct {
	ConversationID string `gorm:"primaryKey"`
	ViewType       int    `gorm:"primaryKey"`
	Reverse        bool   `gorm:"primaryKey"`
	ClientMsgID    string
	Seq            int64
	SendTime       int64
}

func (messageCacheCursor) TableName() string { return "sdk_message_cache_cursors_v1" }

func (d *DataBase) SaveMessageCacheCursors(ctx context.Context, id string, view int, reverse, reset bool, rows []*model_struct.LocalChatLog) error {
	var first, last *model_struct.LocalChatLog
	for _, row := range rows {
		if row.Seq <= 0 {
			continue
		}
		if first == nil || row.Seq < first.Seq {
			first = row
		}
		if last == nil || row.Seq > last.Seq {
			last = row
		}
	}
	if first == nil {
		return nil
	}
	var cursors []messageCacheCursor
	if !reverse || reset {
		cursors = append(cursors, messageCacheCursor{id, view, false, first.ClientMsgID, first.Seq, first.SendTime})
	}
	if reverse || reset {
		cursors = append(cursors, messageCacheCursor{id, view, true, last.ClientMsgID, last.Seq, last.SendTime})
	}
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	return d.conn.WithContext(ctx).Clauses(clause.OnConflict{UpdateAll: true}).Create(&cursors).Error
}

func (d *DataBase) GetMessageCacheAnchor(ctx context.Context, id, msgID string) (*model_struct.LocalChatLog, error) {
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	var a messageCacheAnchor
	if err := d.conn.WithContext(ctx).Where("conversation_id = ? AND client_msg_id = ?", id, msgID).Take(&a).Error; err != nil {
		if err != gorm.ErrRecordNotFound {
			return nil, err
		}
		var cursor messageCacheCursor
		if err := d.conn.WithContext(ctx).Where("conversation_id = ? AND client_msg_id = ?", id, msgID).Take(&cursor).Error; err != nil {
			return nil, err
		}
		return &model_struct.LocalChatLog{ClientMsgID: cursor.ClientMsgID, Seq: cursor.Seq, SendTime: cursor.SendTime}, nil
	}
	return &model_struct.LocalChatLog{ClientMsgID: a.ClientMsgID, Seq: a.Seq, SendTime: a.SendTime}, nil
}

// MaintainMessageCache is called after durable delivery, and after a history
// result is built. Eviction never changes unread, summaries or sync coverage.
func (d *DataBase) MaintainMessageCache(ctx context.Context, id string, touchedIDs []string) error {
	if err := d.initChatLog(ctx, id); err != nil {
		return err
	}
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	return d.conn.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		table := utils.GetConversationTableName(id)
		now := time.Now().UnixNano()
		// Import at most a cache window from an older SDK. Already-indexed rows
		// retain their access age; freshly fetched history is explicitly touched.
		var rows []*model_struct.LocalChatLog
		var initialized int64
		if err := tx.Model(&messageCacheConversation{}).Where("conversation_id = ?", id).Count(&initialized).Error; err != nil {
			return err
		}
		if initialized == 0 {
			if err := tx.Table(table).Where("seq > 0 AND status = ? AND coalesce(content_type,0) != ?", constant.MsgStatusSendSuccess, constant.RevokeNotification).Order("seq DESC").Limit(MessageCacheConversationLimit).Find(&rows).Error; err != nil {
				return err
			}
		}
		if len(touchedIDs) > 0 {
			var touched []*model_struct.LocalChatLog
			if err := tx.Table(table).Where("client_msg_id IN ? AND seq > 0 AND status = ? AND coalesce(content_type,0) != ?", touchedIDs, constant.MsgStatusSendSuccess, constant.RevokeNotification).Find(&touched).Error; err != nil {
				return err
			}
			rows = append(rows, touched...)
		}
		touched := make(map[string]bool, len(touchedIDs))
		for _, msgID := range touchedIDs {
			touched[msgID] = true
		}
		entries := make(map[string]messageCacheEntry)
		for _, row := range rows {
			age := row.SendTime * int64(time.Millisecond)
			if touched[row.ClientMsgID] {
				age = now
			}
			entries[row.ClientMsgID] = messageCacheEntry{ConversationID: id, ClientMsgID: row.ClientMsgID, Seq: row.Seq, SendTime: row.SendTime, Touched: age,
				Bytes: int64(len(row.Content) + len(row.AttachedInfo) + len(row.Ex) + len(row.LocalEx) + len(row.ClientMsgID) + len(row.ServerMsgID) + len(row.SenderNickname) + len(row.SenderFaceURL) + 256)}
		}
		batch := make([]messageCacheEntry, 0, len(entries))
		for _, entry := range entries {
			batch = append(batch, entry)
		}
		if len(batch) > 0 {
			if err := tx.Clauses(clause.OnConflict{Columns: []clause.Column{{Name: "conversation_id"}, {Name: "client_msg_id"}}, DoUpdates: clause.AssignmentColumns([]string{"bytes", "seq", "send_time"})}).CreateInBatches(batch, 100).Error; err != nil {
				return err
			}
			if len(touchedIDs) > 0 {
				if err := tx.Model(&messageCacheEntry{}).Where("conversation_id = ? AND client_msg_id IN ?", id, touchedIDs).Update("touched", now).Error; err != nil {
					return err
				}
			}
		}
		// Compact legacy cache without touching pending sends or local deletes.
		if initialized == 0 {
			// Legacy recall rows are themselves durable tombstones. Keep them
			// even if this SDK has not yet observed their notification journal.
			if err := tx.Exec(fmt.Sprintf("DELETE FROM `%s` WHERE seq > 0 AND status = ? AND coalesce(content_type,0) != ? AND client_msg_id NOT IN (SELECT client_msg_id FROM sdk_message_cache_v1 WHERE conversation_id = ?)", table), constant.MsgStatusSendSuccess, constant.RevokeNotification, id).Error; err != nil {
				return err
			}
			if err := tx.Create(&messageCacheConversation{ConversationID: id}).Error; err != nil {
				return err
			}
		}
		deleted := tx.Table(table).Where("status >= ?", constant.MsgStatusHasDeleted)
		if initialized != 0 {
			deleted = deleted.Where("client_msg_id IN ?", touchedIDs)
		}
		if err := deleted.Update("content", "").Error; err != nil {
			return err
		}
		var victims []messageCacheEntry
		if err := tx.Where("conversation_id = ?", id).Order("touched DESC, seq DESC").Offset(MessageCacheConversationLimit).Find(&victims).Error; err != nil {
			return err
		}
		if err := evictMessageCache(tx, victims); err != nil {
			return err
		}
		var totals struct {
			Count int64
			Bytes int64
		}
		if err := tx.Model(&messageCacheEntry{}).Select("count(*) AS count, coalesce(sum(bytes),0) AS bytes").Scan(&totals).Error; err != nil {
			return err
		}
		for totals.Count > MessageCacheAccountLimit || totals.Bytes > MessageCacheByteLimit {
			var oldest []messageCacheEntry
			if err := tx.Order("touched ASC, seq ASC").Limit(100).Find(&oldest).Error; err != nil {
				return err
			}
			if len(oldest) == 0 {
				break
			}
			if err := evictMessageCache(tx, oldest); err != nil {
				return err
			}
			for _, v := range oldest {
				totals.Count--
				totals.Bytes -= v.Bytes
			}
		}
		return tx.Exec("DELETE FROM sdk_message_cache_anchors_v1 WHERE rowid IN (SELECT rowid FROM sdk_message_cache_anchors_v1 ORDER BY touched DESC LIMIT -1 OFFSET ?)", MessageCacheAccountLimit).Error
	})
}

func evictMessageCache(tx *gorm.DB, victims []messageCacheEntry) error {
	groups := make(map[string][]string)
	anchors := make([]messageCacheAnchor, 0, len(victims))
	for _, v := range victims {
		groups[v.ConversationID] = append(groups[v.ConversationID], v.ClientMsgID)
		anchors = append(anchors, messageCacheAnchor{v.ConversationID, v.ClientMsgID, v.Seq, v.SendTime, time.Now().UnixNano()})
	}
	if len(anchors) > 0 {
		if err := tx.Clauses(clause.OnConflict{UpdateAll: true}).CreateInBatches(anchors, 100).Error; err != nil {
			return err
		}
	}
	for id, ids := range groups {
		for begin := 0; begin < len(ids); begin += 100 {
			page := ids[begin:min(begin+100, len(ids))]
			if err := tx.Table(utils.GetConversationTableName(id)).Where("client_msg_id IN ? AND seq > 0 AND status = ? AND coalesce(content_type,0) != ?", page, constant.MsgStatusSendSuccess, constant.RevokeNotification).Delete(&model_struct.LocalChatLog{}).Error; err != nil {
				return err
			}
			if err := tx.Where("conversation_id = ? AND client_msg_id IN ?", id, page).Delete(&messageCacheEntry{}).Error; err != nil {
				return err
			}
		}
	}
	return nil
}
