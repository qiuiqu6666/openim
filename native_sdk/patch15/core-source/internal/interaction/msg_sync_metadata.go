package interaction

import (
	"context"
	"github.com/openimsdk/tools/log"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

const cmdSyncAuxiliaryMetadata = "syncAuxiliaryMetadata"

func (m *MsgSyncer) finishMessageRecovery(ctx context.Context) {
	if ctx.Err() != nil {
		return
	}
	if m.recvCh == nil {
		// Standalone callers without the recovery scheduler keep joined work.
		if err := m.syncMetadataAfterMessages(ctx); err != nil {
			m.reportMessageSyncFailure(ctx, err)
			return
		}
	}
	common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncEnd, m.conversationCh)
	m.requestAuxiliaryMetadata()
}

func (m *MsgSyncer) requestAuxiliaryMetadata() {
	if m.recvCh == nil {
		return
	}
	if !m.auxMetadataPending {
		m.auxMetadataProgress = &common.MetadataProgress{}
	}
	m.auxMetadataPending = true
	m.queuePendingAuxiliaryMetadata()
}

func (m *MsgSyncer) queuePendingAuxiliaryMetadata() {
	if !m.auxMetadataPending || m.recvCh == nil || m.ctx.Err() != nil {
		return
	}
	select {
	case m.recvCh <- common.Cmd2Value{Ctx: common.WithPreparedRecoveryMetadata(m.ctx), Cmd: cmdSyncAuxiliaryMetadata}:
	default:
	}
}

func (m *MsgSyncer) doAuxiliaryMetadataSync(ctx context.Context) {
	if !m.auxMetadataPending {
		return
	}
	ctx = common.WithMetadataProgress(ctx, m.auxMetadataProgress)
	before := m.auxMetadataProgress.Checkpoints()
	err := m.syncMetadataAfterMessages(ctx)
	if owner, ok := ctx.Value(messagePageContextKey{}).(*messagePageCoordinator); ok {
		owner.committed.Add(m.auxMetadataProgress.Checkpoints() - before)
	}
	if err != nil {
		// Retry on the same serialized scheduler. Auxiliary profile failures
		// never turn already committed messages into a failed network recovery.
		recordMessageSyncFailure(ctx, err)
		log.ZWarn(ctx, "auxiliary metadata synchronization deferred", err)
		return
	}
	m.auxMetadataPending = false
	m.auxMetadataProgress = nil
}

// Keep metadata failures visible and retryable, but only after offline messages
// have been persisted and published. The existing interruptible conversation
// worker owns this work; no untracked goroutine can outlive the login session.
func (m *MsgSyncer) syncMetadataAfterMessages(ctx context.Context) error {
	return common.SendSyncCmdWithReceipt(ctx, common.Cmd2Value{
		Cmd:   constant.CmdSyncData,
		Value: sdk_struct.CmdNewMsgComeToConversation{},
	}, m.conversationCh)
}
