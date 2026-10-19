//go:build !js

package db

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
)

// GetVersionSyncHeaders deliberately excludes id_list. Probing unchanged groups
// must not deserialize every member ID in every joined group. These partial rows
// are read-only and must never be passed to SetVersionSync.
func (d *DataBase) GetVersionSyncHeaders(ctx context.Context, table string, ids []string) (map[string]*model_struct.LocalVersionSync, error) {
	result := make(map[string]*model_struct.LocalVersionSync, len(ids))
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		return result, nil
	}
	d.mRWMutex.RLock()
	defer d.mRWMutex.RUnlock()
	// Stay below SQLite's parameter limit even when called outside group sync.
	for start := 0; start < len(ids); start += 200 {
		end := min(start+200, len(ids))
		var rows []*model_struct.LocalVersionSync
		err := d.conn.WithContext(ctx).Select("table_name", "entity_id", "version_id", "version").
			Where("table_name = ? AND entity_id IN ?", table, ids[start:end]).Find(&rows).Error
		if err != nil {
			return nil, errs.Wrap(err)
		}
		for _, row := range rows {
			result[row.EntityID] = row
		}
	}
	return result, nil
}
