package group

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/group"
)

// A permission error alone is not proof of departure. Reconcile against a
// complete authoritative membership snapshot before retiring any obligation.
// Do not touch messages or conversation history.
func (g *Group) retireDepartedMemberRequests(ctx context.Context, scope string, requests []*group.GetIncrementalGroupMemberReq) ([]*group.GetIncrementalGroupMemberReq, error) {
	joined, err := g.getFullJoinGroupIDs(ctx, &group.GetFullJoinGroupIDsReq{UserID: g.loginUserID})
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	active := make(map[string]bool, len(joined.GroupIDs))
	for _, id := range joined.GroupIDs {
		active[id] = true
	}
	pending := make([]*group.GetIncrementalGroupMemberReq, 0, len(requests))
	departed := make(map[string]bool)
	for _, req := range requests {
		if active[req.GroupID] {
			pending = append(pending, req)
		} else {
			departed[req.GroupID] = true
		}
	}
	if len(departed) == 0 {
		return pending, nil
	}
	local, err := g.db.GetJoinedGroupListDB(ctx)
	if err != nil {
		return nil, err
	}
	var removed []*model_struct.LocalGroup
	for _, row := range local {
		if row != nil && departed[row.GroupID] {
			removed = append(removed, row)
		}
	}
	// Invalidate the joined-list cursor first: its UIDList must not keep
	// resurrecting retired jobs. A failed cleanup remains retryable.
	if err := g.db.DeleteVersionSync(ctx, g.groupTableName(), g.loginUserID); err != nil {
		return nil, err
	}
	// Reuse normal departure cleanup and listener ownership. Only the confirmed
	// departed rows participate; unrelated local groups are preserved.
	if err := g.groupSyncer.Sync(ctx, nil, removed, nil); err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	for id := range departed {
		common.CompleteMetadataItem(ctx, scope, id)
	}
	return pending, nil
}
