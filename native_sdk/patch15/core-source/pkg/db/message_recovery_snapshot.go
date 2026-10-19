//go:build !js

package db

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
)

func (d *DataBase) GetMessageRecoveryVersions(ctx context.Context, table string) ([]*model_struct.LocalVersionSync, error) {
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	var rows []*model_struct.LocalVersionSync
	err := d.conn.WithContext(ctx).Where("table_name = ?", table).Find(&rows).Error
	return rows, errs.Wrap(err)
}

func (d *DataBase) GetMessageRecoveryBounds(ctx context.Context) ([]*model_struct.LocalConversation, error) {
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	var rows []*model_struct.LocalConversation
	err := d.conn.WithContext(ctx).Select("conversation_id", "min_seq", "max_seq", "latest_msg_send_time", "is_pinned").Find(&rows).Error
	return rows, errs.Wrap(err)
}
