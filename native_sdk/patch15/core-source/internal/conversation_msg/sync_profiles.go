package conversation_msg

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type profilesPreparedKey struct{}

// Populate profile caches in bounded batches before the syncer's per-row insert
// callbacks. Retried initial sync otherwise requests every missing group alone.
func (c *Conversation) syncConversationsWithProfiles(ctx context.Context, server, local []*model_struct.LocalConversation) error {
	existing := make(map[string]bool, len(local))
	for _, item := range local {
		existing[item.ConversationID] = true
	}
	var missing []*model_struct.LocalConversation
	for _, item := range server {
		if !existing[item.ConversationID] {
			missing = append(missing, item)
		}
	}
	for start := 0; start < len(missing); start += 100 {
		end := start + 100
		if end > len(missing) {
			end = len(missing)
		}
		if err := c.batchAddFaceURLAndName(ctx, missing[start:end]...); err != nil {
			return err
		}
		common.ReportSyncProgress(ctx)
	}
	return c.conversationSyncer.Sync(context.WithValue(ctx, profilesPreparedKey{}, true), server, local, nil, true)
}
