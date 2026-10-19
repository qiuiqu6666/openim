package group

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/protocol/group"
	"github.com/openimsdk/tools/errs"
)

// The server stops after its changed-member response budget. A group omitted
// from a nonempty response may not have been inspected; it is not a checkpoint.
func (g *Group) syncMemberRequests(ctx context.Context, scope string, requests []*group.GetIncrementalGroupMemberReq) error {
	for len(requests) > 0 {
		if err := ctx.Err(); err != nil {
			return err
		}
		responses, err := g.getIncrementalGroupMemberBatch(ctx, requests)
		if err != nil {
			return err
		}
		// The existing server skips dismissed groups. An entirely empty success
		// cannot have reached the response budget, so all remaining were checked.
		if len(responses) == 0 {
			for _, req := range requests {
				common.CompleteMetadataItem(ctx, scope, req.GroupID)
			}
			return ctx.Err()
		}
		pending := make([]*group.GetIncrementalGroupMemberReq, 0, len(requests))
		tasks := make([]func() error, 0, len(requests))
		for _, req := range requests {
			id := req.GroupID
			resp, present := responses[id]
			if !present {
				pending = append(pending, req)
				continue
			}
			if unchangedMemberVersion(req, resp) {
				common.CompleteMetadataItem(ctx, scope, id)
				continue
			}
			tasks = append(tasks, func() error {
				if resp == nil {
					return errs.New("nil incremental group response", "groupID", id)
				}
				if err := g.syncGroupAndMember(ctx, id, resp); err != nil {
					return err
				}
				common.CompleteMetadataItem(ctx, scope, id)
				return nil
			})
		}
		if len(pending) == len(requests) {
			return errs.New("group batch response made no progress")
		}
		if err := runGroupSyncBatch(ctx, tasks); err != nil {
			return err
		}
		requests = pending
	}
	return ctx.Err()
}
