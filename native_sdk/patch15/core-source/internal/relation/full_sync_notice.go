package relation

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

// FullSync replaces the table in batches without the incremental syncer's
// notices. Message readiness can precede this auxiliary job, so publish the
// committed roster changes independently of OnSyncServerFinish.
func syncFullFriendsWithNotice(
	ctx context.Context,
	load func(context.Context) ([]*model_struct.LocalFriend, error),
	sync func(context.Context) error,
	listener open_im_sdk_callback.OnFriendshipListenerSdk,
) error {
	before, err := load(ctx)
	if err != nil {
		return err
	}
	if err := sync(ctx); err != nil {
		return err
	}
	after, err := load(ctx)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if listener == nil {
		return nil
	}
	previous := make(map[string]*model_struct.LocalFriend, len(before))
	for _, friend := range before {
		previous[friend.FriendUserID] = friend
	}
	current := make(map[string]struct{}, len(after))
	for _, friend := range after {
		current[friend.FriendUserID] = struct{}{}
		old, found := previous[friend.FriendUserID]
		if !found {
			listener.OnFriendAdded(*friend)
		} else if *old != *friend {
			listener.OnFriendInfoChanged(*friend)
		}
	}
	for _, friend := range before {
		if _, found := current[friend.FriendUserID]; !found {
			listener.OnFriendDeleted(*friend)
		}
	}
	return nil
}
