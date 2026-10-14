// Copyright © 2023 OpenIM SDK. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//go:build !js
// +build !js

package db

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func (d *DataBase) SetNotificationSeq(ctx context.Context, conversationID string, seq int64) error {
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	cursor := d.conn.WithContext(ctx).Model(&model_struct.NotificationSeqs{}).Where("conversation_id = ?", conversationID).Updates(map[string]interface{}{"seq": seq})
	if cursor.Error != nil {
		return errs.WrapMsg(cursor.Error, "Updates failed")
	}
	if cursor.RowsAffected == 0 {
		return errs.WrapMsg(d.conn.WithContext(ctx).Create(&model_struct.NotificationSeqs{ConversationID: conversationID, Seq: seq}).Error, "Create failed")
	}
	return nil
}

func (d *DataBase) BatchInsertNotificationSeq(ctx context.Context, notificationSeqs []*model_struct.NotificationSeqs) error {
	if len(notificationSeqs) == 0 {
		return nil
	}
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	// Initial message pulls may fail after this baseline is already durable.
	// Retrying bootstrap (also after restart) must be idempotent. A stale
	// response must not rewind the notification cursor and replay side effects.
	return errs.WrapMsg(d.conn.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "conversation_id"}},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"seq": gorm.Expr("MAX(seq, excluded.seq)"),
		}),
	}).CreateInBatches(notificationSeqs, 200).Error, "BatchInsertNotificationSeq failed")
}

func (d *DataBase) GetNotificationAllSeqs(ctx context.Context) ([]*model_struct.NotificationSeqs, error) {
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	var seqs []*model_struct.NotificationSeqs
	return seqs, errs.WrapMsg(d.conn.WithContext(ctx).Where("1=1").Find(&seqs).Error, "GetNotificationAllSeqs failed")
}
