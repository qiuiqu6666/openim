package relation

import (
	"context"
	"fmt"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

const friendProfileBatchSize = 100

// SyncFriendsWithProfilesWithLock runs in the existing auxiliary recovery job.
// Roster versions alone cannot repair a profile missed by an older client.
// Bound requests, retain offline data, and retry incomplete passes next time.
func (r *Relation) SyncFriendsWithProfilesWithLock(ctx context.Context) error {
	r.relationSyncMutex.Lock()
	defer r.relationSyncMutex.Unlock()
	if err := r.IncrSyncFriends(ctx); err != nil {
		return err
	}
	if time.Since(r.friendProfilesSyncedAt) < time.Minute {
		return nil
	}
	friends, err := r.db.GetAllFriendList(ctx)
	if err != nil {
		return err
	}
	for start := 0; start < len(friends); start += friendProfileBatchSize {
		end := min(start+friendProfileBatchSize, len(friends))
		ids := make([]string, 0, end-start)
		for _, friend := range friends[start:end] {
			ids = append(ids, friend.FriendUserID)
		}
		if err := r.refreshFriendProfiles(ctx, ids); err != nil {
			return err
		}
	}
	if err := ctx.Err(); err != nil {
		return err
	}
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
