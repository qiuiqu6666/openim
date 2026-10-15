package interaction

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func (m *MsgSyncer) readStartupCheckpoints(ctx context.Context) (map[string]*model_struct.LocalVersionSync, error) {
	reader, ok := m.db.(db_interface.MessageCheckpointReader)
	if !ok {
		return nil, nil
	}
	rows, err := reader.GetMessageRecoveryVersions(ctx, messageCheckpointTable)
	if err != nil {
		return nil, err
	}
	byID := make(map[string]*model_struct.LocalVersionSync, len(rows))
	for _, row := range rows {
		if row != nil {
			byID[row.EntityID] = row
		}
	}
	return byID, nil
}
