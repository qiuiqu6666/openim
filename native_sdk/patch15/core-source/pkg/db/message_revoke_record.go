//go:build !js

package db

import (
	"context"
	"encoding/json"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// Recall state survives eviction of the message body. It is not a cached body.
type messageRevokeRecord struct {
	ConversationID string `gorm:"primaryKey"`
	Seq            int64  `gorm:"primaryKey"`
	Tips           string
}

func (messageRevokeRecord) TableName() string { return "sdk_message_revocations_v1" }

func (d *DataBase) SaveMessageRevocation(ctx context.Context, tips *sdkws.RevokeMsgTips) error {
	data, err := json.Marshal(tips)
	if err != nil {
		return err
	}
	d.mRWMutex.Lock()
	defer d.mRWMutex.Unlock()
	return d.conn.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(&messageRevokeRecord{ConversationID: tips.ConversationID, Seq: tips.Seq, Tips: string(data)}).Error
}

func (d *DataBase) ApplyMessageRevocations(ctx context.Context, id string, rows []*model_struct.LocalChatLog) error {
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	return applyMessageRevocations(d.conn.WithContext(ctx), id, rows)
}

func applyMessageRevocations(tx *gorm.DB, id string, rows []*model_struct.LocalChatLog) error {
	seqs := make([]int64, 0, len(rows))
	for _, row := range rows {
		if row.Seq > 0 {
			seqs = append(seqs, row.Seq)
		}
	}
	if len(seqs) == 0 {
		return nil
	}
	var records []messageRevokeRecord
	if err := tx.Where("conversation_id = ? AND seq IN ?", id, seqs).Find(&records).Error; err != nil {
		return err
	}
	bySeq := make(map[int64]*sdkws.RevokeMsgTips, len(records))
	for _, record := range records {
		var tips sdkws.RevokeMsgTips
		if err := json.Unmarshal([]byte(record.Tips), &tips); err != nil {
			return err
		}
		bySeq[record.Seq] = &tips
	}
	for _, row := range rows {
		tips := bySeq[row.Seq]
		if tips == nil || row.ContentType == constant.RevokeNotification || row.Status >= constant.MsgStatusHasDeleted {
			continue
		}
		nickname := ""
		if tips.RevokerUserID == row.SendID {
			nickname = row.SenderNickname
		}
		payload, err := json.Marshal(sdk_struct.MessageRevoked{RevokerID: tips.RevokerUserID, ClientMsgID: row.ClientMsgID, RevokerNickname: nickname, RevokeTime: tips.RevokeTime, SourceMessageSendTime: row.SendTime, SourceMessageSendID: row.SendID, SourceMessageSenderNickname: row.SenderNickname, SessionType: tips.SesstionType, Seq: tips.Seq, Ex: row.Ex, IsAdminRevoke: tips.IsAdminRevoke})
		if err != nil {
			return err
		}
		content, err := json.Marshal(sdk_struct.NotificationElem{Detail: string(payload)})
		if err != nil {
			return err
		}
		row.ContentType = constant.RevokeNotification
		row.Content = string(content)
	}
	return nil
}
