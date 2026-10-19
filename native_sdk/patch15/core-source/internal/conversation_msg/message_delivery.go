package conversation_msg

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
)

// Stored before the message batch, cleared after callbacks. The range journal
// replays an interrupted batch, including after a process restart. Delivery is
// at least once: consumers must continue merging by message identity.
const messageDeliveryTable = "sdk_message_delivery_v1"

func (c *Conversation) loadMessageDeliveries(ctx context.Context, id string) (map[string]int64, error) {
	row, err := c.db.GetVersionSync(ctx, messageDeliveryTable, id)
	if errors.Is(err, errs.ErrRecordNotFound) {
		return make(map[string]int64), nil
	}
	if err != nil {
		return nil, err
	}
	pending := make(map[string]int64)
	if row.VersionID != "" {
		if err := json.Unmarshal([]byte(row.VersionID), &pending); err != nil {
			return nil, err
		}
	}
	if pending == nil {
		pending = make(map[string]int64)
	}
	return pending, nil
}

func (c *Conversation) saveMessageDeliveries(ctx context.Context, id string, pending map[string]int64) error {
	payload, err := json.Marshal(pending)
	if err != nil {
		return err
	}
	return c.db.SetVersionSync(ctx, &model_struct.LocalVersionSync{
		Table: messageDeliveryTable, EntityID: id, Version: 1, VersionID: string(payload),
	})
}
