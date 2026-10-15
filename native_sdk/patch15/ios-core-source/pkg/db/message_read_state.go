//go:build !js

package db

import (
	"context"
	"encoding/json"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type messageReadState struct {
	ConversationID string `gorm:"primaryKey"`
	Self           bool   `gorm:"primaryKey"`
	Seq            int64
	ReadTime       int64
}

func (messageReadState) TableName() string { return "sdk_message_read_state_v1" }

func (d *DataBase) SaveMessageReadWatermarks(ctx context.Context, seqs map[string]int64, self bool, readTime int64) error {
	rows := make([]messageReadState, 0, len(seqs))
	for id, seq := range seqs {
		if seq > 0 {
			rows = append(rows, messageReadState{ConversationID: id, Self: self, Seq: seq, ReadTime: readTime})
		}
	}
	if len(rows) == 0 {
		return nil
	}
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	return d.conn.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "conversation_id"}, {Name: "self"}},
		DoUpdates: clause.AssignmentColumns([]string{"seq", "read_time"}),
		Where:     clause.Where{Exprs: []clause.Expression{clause.Expr{SQL: "excluded.seq > sdk_message_read_state_v1.seq"}}},
	}).CreateInBatches(rows, 100).Error
}

func (d *DataBase) ApplyMessageReadWatermarks(ctx context.Context, id string, rows []*model_struct.LocalChatLog) error {
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	return applyMessageReadWatermarks(d.conn.WithContext(ctx), id, d.loginUserID, rows)
}

func applyMessageReadWatermarks(tx *gorm.DB, id, loginID string, rows []*model_struct.LocalChatLog) error {
	if len(rows) == 0 {
		return nil
	}
	var states []messageReadState
	if err := tx.Where("conversation_id = ?", id).Find(&states).Error; err != nil {
		return err
	}
	for _, state := range states {
		for _, row := range rows {
			if row.Seq <= 0 || row.Seq > state.Seq || (row.SendID == loginID) == state.Self {
				continue
			}
			row.IsRead = true
			if state.ReadTime > 0 {
				var attached sdk_struct.AttachedInfoElem
				_ = json.Unmarshal([]byte(row.AttachedInfo), &attached)
				attached.HasReadTime = max(attached.HasReadTime, state.ReadTime)
				payload, err := json.Marshal(attached)
				if err != nil {
					return err
				}
				row.AttachedInfo = string(payload)
			}
		}
	}
	return nil
}
