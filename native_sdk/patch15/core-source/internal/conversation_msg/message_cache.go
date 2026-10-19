package conversation_msg

import (
	"context"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/log"
	"gorm.io/gorm"
	"time"
)

func isLocalRecordMissing(err error) bool {
	return errors.Is(err, errs.ErrRecordNotFound) || errors.Is(err, gorm.ErrRecordNotFound)
}

func (c *Conversation) maintainMessageCache(ctx context.Context, id string, ids []string) {
	started := time.Now()
	defer func() { common.RecordSyncMetric(ctx, "cache_maintenance", 1, time.Since(started)) }()
	if store, ok := c.db.(interface {
		MaintainMessageCache(context.Context, string, []string) error
	}); ok {
		if err := store.MaintainMessageCache(ctx, id, ids); err != nil {
			// Delivery already succeeded. Retry maintenance on the next access;
			// never turn a cache failure into duplicate message arrival.
			log.ZWarn(ctx, "message cache maintenance failed", err, "conversationID", id)
		}
	}
}

func (c *Conversation) historyAnchor(ctx context.Context, id, msgID string) (*model_struct.LocalChatLog, error) {
	row, err := c.db.GetMessage(ctx, id, msgID)
	if err == nil {
		return row, nil
	}
	if !isLocalRecordMissing(err) {
		return nil, err
	}
	if store, ok := c.db.(interface {
		GetMessageCacheAnchor(context.Context, string, string) (*model_struct.LocalChatLog, error)
	}); ok {
		return store.GetMessageCacheAnchor(ctx, id, msgID)
	}
	return nil, err
}
