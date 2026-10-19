//go:build !js

package db

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
)

// GetReadWatermarkMessages pages by the server sequence, not by wall-clock
// ordering. Never expand a possibly very large watermark into a sequence list.
func (d *DataBase) GetReadWatermarkMessages(ctx context.Context, id string, after, through int64) (rows []*model_struct.LocalChatLog, err error) {
	if err = d.initChatLog(ctx, id); err != nil {
		return nil, err
	}
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	err = d.conn.WithContext(ctx).Table(utils.GetConversationTableName(id)).
		Where("seq > ? AND seq <= ?", after, through).
		Order("seq ASC").Limit(200).Find(&rows).Error
	return
}
