package db_interface

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

// Optional optimized capability; other database adapters retain the portable
// reconciliation path. Each page commits atomically and returns full SDK rows
// only for profiles that changed, without loading unrelated message payloads.
type GroupConversationProfileSync interface {
	ReconcileGroupConversationProfilePage(ctx context.Context, afterID string, limit int) ([]*model_struct.LocalConversation, error)
}
