package relation

import (
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"testing"
)

func TestNewRecoveryBypassesFriendProfileCooldown(t *testing.T) {
	r, d, _, ctx, calls, mode := friendProfileFixture(t, 1)
	first := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	if err := r.SyncFriendsWithProfilesWithLock(first); err != nil {
		t.Fatal(err)
	}
	*mode = "clear"
	if err := r.SyncFriendsWithProfilesWithLock(first); err != nil {
		t.Fatal(err)
	}
	if *calls != 1 {
		t.Fatal("same recovery lost cooldown")
	}
	next := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	if err := r.SyncFriendsWithProfilesWithLock(next); err != nil {
		t.Fatal(err)
	}
	if *calls != 2 || d.rows["0"].FaceURL != "" {
		t.Fatalf("stale profile: calls=%d row=%+v", *calls, d.rows["0"])
	}
}
