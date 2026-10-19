package conversation_msg

import (
	"context"
	"fmt"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
)

func syncCommandContext(cmd common.Cmd2Value) (context.Context, context.CancelFunc) {
	if !cmd.ExpiresAt.IsZero() {
		return context.WithDeadline(cmd.Ctx, cmd.ExpiresAt)
	}
	return context.WithCancel(cmd.Ctx)
}

// Sync can run inside the conversation worker. Enqueueing to that worker's
// own full channel would block the very consumer that could make space.
// This is called after releasing conversationSyncMutex.
func (c *Conversation) notifySyncedConversations(ctx context.Context, ids []string) error {
	conversations, err := c.db.GetMultipleConversationDB(ctx, ids)
	if err != nil {
		return err
	}
	total, err := c.db.GetTotalUnreadMsgCountDB(ctx)
	if err != nil {
		return err
	}
	var visible []*model_struct.LocalConversation
	for _, conversation := range conversations {
		if conversation.LatestMsgSendTime != 0 {
			visible = append(visible, conversation)
		}
	}
	c.ConversationListener().OnConversationChanged(utils.StructToJsonStringDefault(visible))
	c.ConversationListener().OnTotalUnreadMessageCountChanged(total)
	return nil
}

// Parallel metadata jobs must report failure to their owner; a panic must not
// terminate the process or leave a receipt waiting forever.
func runSyncFunctionSafely(ctx context.Context, fn func(context.Context) error) (err error) {
	defer func() {
		if failure := recover(); failure != nil {
			err = fmt.Errorf("metadata sync panic: %v", failure)
		}
	}()
	if err := ctx.Err(); err != nil {
		return err
	}
	return fn(ctx)
}
