package conversation_msg

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"sync"
	"testing"
	"time"
)

func TestMissingProfileQueueDeduplicatesConcurrentHistoryAndLiveRows(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c := &Conversation{sessionContext: ctx, msgSyncerCh: make(chan common.Cmd2Value, 10)}
	rows := []*model_struct.LocalChatLog{{SendID: "missing"}, {SendID: "complete", SenderNickname: "name", SenderFaceURL: "face"}}
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); c.queueMissingProfiles(ctx, "group", rows) }()
	}
	wg.Wait()
	if len(c.profileQueue.pending["group"]) != 1 || len(c.msgSyncerCh) != 1 {
		t.Fatal("duplicate requests or complete wire profiles queued")
	}
	cancel()
	if err := c.flushMissingProfiles(ctx); err != context.Canceled {
		t.Fatalf("cancel must stop before any group service call: %v", err)
	}
	if len(c.profileQueue.pending["group"]) != 1 {
		t.Fatal("cancellation discarded pending work")
	}
	c.queueMissingProfiles(ctx, "afterLogout", rows)
	if len(c.profileQueue.pending) != 1 {
		t.Fatal("logged-out session accepted work")
	}
}

func TestMissingProfileDeduplicationPreservesGroupIdentity(t *testing.T) {
	ctx := context.Background()
	c := &Conversation{sessionContext: ctx, msgSyncerCh: make(chan common.Cmd2Value, 2)}
	rows := []*model_struct.LocalChatLog{{SendID: "same-user"}}
	c.queueMissingProfiles(ctx, "group-a", rows)
	c.queueMissingProfiles(ctx, "group-b", rows)
	if len(c.profileQueue.pending) != 2 || len(c.msgSyncerCh) != 1 {
		t.Fatal("group-specific nickname/permissions were merged or duplicate wake queued")
	}
}

func TestResolvedEmptyAvatarDoesNotCauseProfileRequestStorm(t *testing.T) {
	ctx := context.Background()
	c := &Conversation{sessionContext: ctx, msgSyncerCh: make(chan common.Cmd2Value, 2)}
	c.profileQueue.checked("group", "no-avatar")
	rows := []*model_struct.LocalChatLog{{SendID: "no-avatar", SenderNickname: "known"}}
	for i := 0; i < 100; i++ {
		c.queueMissingProfiles(ctx, "group", rows)
	}
	if len(c.msgSyncerCh) != 0 || len(c.profileQueue.pending) != 0 {
		t.Fatal("resolved empty avatar queued another request")
	}
	c.profileQueue.recent[profileKey{"group", "no-avatar"}] = time.Now().Add(-2 * time.Minute)
	c.queueMissingProfiles(ctx, "group", rows)
	if len(c.msgSyncerCh) != 1 {
		t.Fatal("profile cooldown prevented later recovery")
	}
	for i := 0; i < 5000; i++ {
		c.profileQueue.checked("group", time.Unix(int64(i), 0).String())
	}
	if len(c.profileQueue.recent) > 4096 {
		t.Fatal("profile cooldown grew without bound")
	}
}
