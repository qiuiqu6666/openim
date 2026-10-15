package group

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
)

// A member response carries one group's profile. Comparing it with all joined
// groups made catchup quadratic and allocated the full directory per group.
func (g *Group) syncGroupProfile(ctx context.Context, groupID string, info *sdkws.GroupInfo) error {
	if info == nil {
		return nil
	}
	if info.GroupID != groupID || groupID == "" {
		return errs.New("group profile does not match requested group")
	}
	local, err := g.db.GetGroups(ctx, []string{groupID})
	if err != nil {
		return err
	}
	// This is a one-row update, never an authoritative joined-group directory.
	return g.groupSyncer.Sync(ctx, []*model_struct.LocalGroup{ServerGroupToLocalGroup(info)}, local, nil, true)
}
