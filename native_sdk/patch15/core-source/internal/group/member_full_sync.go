package group

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/api"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
)

// A full response is still a change to a live directory. Fetch every page
// before applying differences, preserving callbacks and retryable local rows
// if the request fails. A truncated first 1000 members is not a full snapshot.
func (g *Group) syncFullGroupMembers(ctx context.Context, groupID string) error {
	req := &group.GetGroupMemberListReq{GroupID: groupID, Pagination: &sdkws.RequestPagination{ShowNumber: 100}}
	members, err := api.Page(ctx, req, api.GetGroupMemberList.Invoke, (*group.GetGroupMemberListResp).GetMembers)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	server := make([]*model_struct.LocalGroupMember, 0, len(members))
	seen := make(map[string]bool, len(members))
	for _, member := range members {
		if member == nil || member.GroupID != groupID || member.UserID == "" || seen[member.UserID] {
			return errs.New("invalid full group member snapshot", "groupID", groupID)
		}
		seen[member.UserID] = true
		server = append(server, ServerGroupMemberToLocalGroupMember(member))
	}
	local, err := g.db.GetGroupMemberListByGroupID(ctx, groupID)
	if err != nil {
		return err
	}
	// Clear stale cached rows even when the database already contains the same
	// profile (e.g. a previous build performed silent full replacement).
	g.groupMemberCache.DeleteCon(func(_ string, member *model_struct.LocalGroupMember) bool {
		return member != nil && member.GroupID == groupID
	})
	return g.groupMemberSyncer.Sync(ctx, server, local, nil)
}
