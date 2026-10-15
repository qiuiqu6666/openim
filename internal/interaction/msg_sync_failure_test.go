package interaction

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
)

func TestCancelledSyncDoesNotPublishFailureAndRetainsRetry(t *testing.T) {
	for _, cancelledParent := range []bool{false, true} {
		t.Run(map[bool]string{false: "yielded-metadata", true: "cancelled-attempt"}[cancelledParent], func(t *testing.T) {
			session := recoveryContext(t)
			owner := &messagePageCoordinator{}
			ctx, cancel := context.WithCancel(context.WithValue(session, messagePageContextKey{}, owner))
			defer cancel()
			if cancelledParent {
				cancel()
			}
			m := &MsgSyncer{ctx: session, conversationCh: make(chan common.Cmd2Value, 1)}
			m.reportMessageSyncFailure(ctx, context.Canceled)
			if len(m.conversationCh) != 0 {
				t.Fatal("scheduler cancellation was reported as a connection failure")
			}
			if owner.failed.Load() == cancelledParent {
				t.Fatal("active yielded metadata must retain its retry; cancelled owner must not create another")
			}
		})
	}
}

func TestRealSyncFailureRemainsVisibleAndRetryable(t *testing.T) {
	ctx := recoveryContext(t)
	owner := &messagePageCoordinator{}
	ctx = context.WithValue(ctx, messagePageContextKey{}, owner)
	m := &MsgSyncer{ctx: ctx, conversationCh: make(chan common.Cmd2Value, 1)}
	m.reportMessageSyncFailure(ctx, errors.New("storage failed"))
	if len(m.conversationCh) != 1 || !owner.failed.Load() {
		t.Fatal("real failure disappeared")
	}
}
