package relation

import (
	"context"
	"testing"
	"time"
)

func TestFriendProfileResumeDoesNotRefetchCommittedBatches(t *testing.T) {
	r, d, _, base, calls, _ := friendProfileFixture(t, 205)
	ctx, cancel := context.WithCancel(base)
	defer cancel()
	// Cancel immediately after the last commit of the first batch. The completed
	// batch must stay completed even when the next request observes cancellation.
	d.afterUpdate = func() {
		if d.updates == 100 {
			cancel()
		}
	}
	if err := r.SyncFriendsWithProfilesWithLock(ctx); err == nil {
		t.Fatal("cancellation hidden")
	}
	if *calls != 1 || len(r.friendProfilePending) != 105 {
		t.Fatalf("calls=%d pending=%d", *calls, len(r.friendProfilePending))
	}
	d.afterUpdate = nil
	if err := r.SyncFriendsWithProfilesWithLock(base); err != nil {
		t.Fatal(err)
	}
	if *calls != 3 || d.updates != 205 {
		t.Fatalf("replayed completed batch: calls=%d writes=%d", *calls, d.updates)
	}
	if r.friendProfilePending != nil {
		t.Fatal("completed pass retained snapshot")
	}
	r.friendProfilesSyncedAt = time.Now().Add(-2 * time.Minute)
	if err := r.SyncFriendsWithProfilesWithLock(base); err != nil {
		t.Fatal(err)
	}
	if *calls != 6 {
		t.Fatal("new pass incorrectly skipped old batches")
	}
}

func TestFriendProfileResumeRechecksDeletedMembership(t *testing.T) {
	r, d, _, base, _, _ := friendProfileFixture(t, 205)
	ctx, cancel := context.WithCancel(base)
	defer cancel()
	d.afterUpdate = func() {
		if d.updates == 100 {
			cancel()
		}
	}
	_ = r.SyncFriendsWithProfilesWithLock(ctx)
	deleted := r.friendProfilePending[0]
	delete(d.rows, deleted)
	d.afterUpdate = nil
	if err := r.SyncFriendsWithProfilesWithLock(base); err != nil {
		t.Fatal(err)
	}
	if _, exists := d.rows[deleted]; exists {
		t.Fatal("resurrected deleted friend")
	}
	if d.updates != 204 {
		t.Fatalf("writes=%d", d.updates)
	}
}
