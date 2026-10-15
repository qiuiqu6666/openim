package db_interface

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

// Optional native optimizations. External/JS stores retain the existing
// per-record API; neither the persisted format nor the required DB API changes.
type MessageCheckpointReader interface {
	GetMessageRecoveryVersions(context.Context, string) ([]*model_struct.LocalVersionSync, error)
}

type MessageRecoveryBoundsReader interface {
	GetMessageRecoveryBounds(context.Context) ([]*model_struct.LocalConversation, error)
}
