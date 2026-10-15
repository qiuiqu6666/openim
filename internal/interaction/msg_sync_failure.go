package interaction

import (
	"context"
	"errors"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

// A deliberately yielded worker still owes its durable targets, but does not
// describe a broken connection. Preserve the scheduler retry without feeding
// cancellation back into the application's network recovery loop.
func (m *MsgSyncer) reportMessageSyncFailure(ctx context.Context, err error) {
	recordMessageSyncFailure(ctx, err)
	if err == nil || ctx.Err() != nil || errors.Is(err, context.Canceled) {
		return
	}
	common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
}
