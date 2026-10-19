package interaction

import (
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"testing"
)

func TestProfileWakeDoesNotRefreshWholeDirectory(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{ctx: ctx, recvCh: make(chan common.Cmd2Value, 2), conversationCh: make(chan common.Cmd2Value)}
	profileCalls, fullCalls := 0, 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		switch cmd.Cmd {
		case common.CmdSyncMissingProfiles:
			profileCalls++
		case constant.CmdSyncData:
			fullCalls++
		}
		return nil
	})
	m.handlePushMsgAndEvent(common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata, Value: common.ProfileQueueWake{}})
	if profileCalls != 1 || fullCalls != 0 || m.auxMetadataPending {
		t.Fatalf("profile=%d full=%d pending=%v", profileCalls, fullCalls, m.auxMetadataPending)
	}
	m.requestAuxiliaryMetadata()
	m.handlePushMsgAndEvent(common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata, Value: common.ProfileQueueWake{}})
	if fullCalls != 1 {
		t.Fatal("profile wake replaced existing full metadata obligation")
	}
}

func TestProfileLookupFailureRetainsOnlyItsOwnRetry(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{ctx: ctx, recvCh: make(chan common.Cmd2Value, 2), conversationCh: make(chan common.Cmd2Value)}
	calls := 0
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd != common.CmdSyncMissingProfiles {
			t.Error("optional retry launched a full metadata sweep")
		}
		calls++
		if calls == 1 {
			return errors.New("profile unavailable")
		}
		return nil
	})
	m.handlePushMsgAndEvent(common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata, Value: common.ProfileQueueWake{}})
	if !m.auxMetadataPending || !m.auxProfilesOnly {
		t.Fatal("failed optional work was discarded")
	}
	m.queuePendingAuxiliaryMetadata()
	m.handlePushMsgAndEvent(<-m.recvCh)
	if calls != 2 || m.auxMetadataPending {
		t.Fatal("optional work did not recover")
	}
}
