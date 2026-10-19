package group

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
)

// Reuse the existing member-profile event for row-level client refreshes.
func (g *Group) PublishMessageProfile(ctx context.Context, member *model_struct.LocalGroupMember) {
	if ctx.Err() == nil && g.listener != nil && member != nil {
		g.listener().OnGroupMemberInfoChanged(utils.StructToJsonString(member))
	}
}
