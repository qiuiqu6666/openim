package conversation_msg

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
)

func metadataStage(name string, run func(context.Context) error) func(context.Context) error {
	return func(ctx context.Context) error { return common.RunMetadataStage(ctx, name, run) }
}
