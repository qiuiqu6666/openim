package relation

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

const friendProfileBatchSize = 100

// SyncFriendsWithProfilesWithLock runs in the existing auxiliary recovery job.
// Roster versions alone cannot repair a profile missed by an older client.
// Bound requests, retain offline data, and retry incomplete passes next time.
func (r *Relation) SyncFriendsWithProfilesWithLock(ctx context.Context) error {
	r.relationSyncMutex.Lock()
	defer r.relationSyncMutex.Unlock()
	// New recovery rechecks profiles even within the normal cooldown.
	// Retries share this progress identity and retain incomplete batches.
	if progress := common.MetadataRecoveryProgress(ctx); progress != nil && progress != r.friendProfileRecovery {
		r.friendProfileRecovery = progress
		r.friendProfilePending = nil
		r.friendProfilesSyncedAt = time.Time{}
	}
	if err := r.IncrSyncFriends(ctx); err != nil {
		return err
	}
	if time.Since(r.friendProfilesSyncedAt) < time.Minute {
		return nil
	}
	// A successful batch is a checkpoint, not a reason to restart the pass.
	// Keep the ID snapshot across preemption; refreshFriendProfiles rechecks
	// membership so a deleted friend is never restored from this snapshot.
	if r.friendProfilePending == nil {
		friends, err := r.db.GetAllFriendList(ctx)
		if err != nil {
			return err
		}
		r.friendProfilePending = make([]string, 0, len(friends))
		for _, friend := range friends {
			r.friendProfilePending = append(r.friendProfilePending, friend.FriendUserID)
		}
		sort.Strings(r.friendProfilePending)
	}
	for len(r.friendProfilePending) > 0 {
		end := min(friendProfileBatchSize, len(r.friendProfilePending))
		if err := r.refreshFriendProfiles(ctx, r.friendProfilePending[:end]); err != nil {
			return err
		}
		common.RecordMetadataCheckpoint(ctx)
		clear(r.friendProfilePending[:end])
		r.friendProfilePending = r.friendProfilePending[end:]
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	r.friendProfilePending = nil
	r.friendProfilesSyncedAt = time.Now()
	return nil
}

// Caller holds relationSyncMutex. Only refresh persisted relationships: a
// profile event must never re-add a deleted friend or replace a user's remark
// with a group nickname. The designated-friend endpoint returns both fields.
func (r *Relation) refreshFriendProfiles(ctx context.Context, ids []string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	local, err := r.db.GetFriendInfoList(ctx, ids)
	if err != nil || len(local) == 0 {
		return err
	}
	wanted := make(map[string]bool, len(local))
	ids = make([]string, 0, len(local))
	for _, friend := range local {
		wanted[friend.FriendUserID] = false
		ids = append(ids, friend.FriendUserID)
	}
	response, err := r.getDesignatedFriends(ctx, ids)
	if err != nil {
		return err
	}
	server := make([]*model_struct.LocalFriend, 0, len(local))
	for _, friend := range response {
		if friend == nil || friend.FriendUser == nil || friend.OwnerUserID != r.loginUserID {
			return fmt.Errorf("invalid friend profile response")
		}
		seen, requested := wanted[friend.FriendUser.UserID]
		if !requested || seen {
			return fmt.Errorf("unexpected or duplicate friend profile response")
		}
		wanted[friend.FriendUser.UserID] = true
		server = append(server, ServerFriendToLocalFriend(friend))
	}
	if len(server) != len(local) {
		return fmt.Errorf("incomplete friend profile response: got %d want %d", len(server), len(local))
	}
	// Use the normal commit/cache invalidation/notices path. Never delete a
	// relationship on a missing or partial profile response.
	return r.friendSyncer.Sync(ctx, server, local, nil, true)
}
