package conversation_msg

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func (c *Conversation) persistMessageSyncBatch(ctx context.Context, updates, inserts map[string][]*model_struct.LocalChatLog, changed, added []*model_struct.LocalConversation) error {
	if atomic, ok := c.db.(interface {
		CommitMessageSyncBatch(context.Context, map[string][]*model_struct.LocalChatLog, map[string][]*model_struct.LocalChatLog, []*model_struct.LocalConversation, []*model_struct.LocalConversation) error
	}); ok {
		return atomic.CommitMessageSyncBatch(ctx, updates, inserts, changed, added)
	}
	// Non-SQLite adapters retain the durable range obligation on any failure.
	if err := c.batchUpdateMessageList(ctx, updates); err != nil {
		return err
	}
	if err := c.batchInsertMessageList(ctx, inserts); err != nil {
		return err
	}
	if err := c.db.BatchUpdateConversationList(ctx, changed); err != nil {
		return err
	}
	return c.db.BatchInsertConversationList(ctx, added)
}
