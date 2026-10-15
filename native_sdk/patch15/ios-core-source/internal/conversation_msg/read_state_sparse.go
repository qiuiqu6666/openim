package conversation_msg

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type sparseReadStore interface {
	SaveMessageReadWatermarks(context.Context, map[string]int64, bool, int64) error
	ApplyMessageReadWatermarks(context.Context, string, []*model_struct.LocalChatLog) error
}

func (c *Conversation) saveReadWatermarks(ctx context.Context, seqs map[string]int64, self bool, readTime int64) error {
	if store, ok := c.db.(sparseReadStore); ok {
		return store.SaveMessageReadWatermarks(ctx, seqs, self, readTime)
	}
	return nil
}
