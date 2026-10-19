package group

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/group"
	"github.com/openimsdk/tools/errs"
)

// Optional capability keeps the existing database contract and WASM fallback.
type versionHeaderReader interface {
	GetVersionSyncHeaders(context.Context, string, []string) (map[string]*model_struct.LocalVersionSync, error)
}

func (g *Group) memberVersionRequests(ctx context.Context, ids []string) ([]*group.GetIncrementalGroupMemberReq, error) {
	versions := make(map[string]*model_struct.LocalVersionSync, len(ids))
	if reader, ok := g.db.(versionHeaderReader); ok {
		var err error
		versions, err = reader.GetVersionSyncHeaders(ctx, g.groupAndMemberVersionTableName(), ids)
		if err != nil {
			return nil, err
		}
	} else {
		for _, id := range ids {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			version, err := g.db.GetVersionSync(ctx, g.groupAndMemberVersionTableName(), id)
			if err != nil && !errs.ErrRecordNotFound.Is(err) {
				return nil, err
			}
			if err == nil {
				versions[id] = version
			}
		}
	}
	requests := make([]*group.GetIncrementalGroupMemberReq, 0, len(ids))
	for _, id := range ids {
		request := &group.GetIncrementalGroupMemberReq{GroupID: id}
		if version := versions[id]; version != nil {
			request.VersionID, request.Version = version.VersionID, version.Version
		}
		requests = append(requests, request)
	}
	return requests, ctx.Err()
}

func unchangedMemberVersion(req *group.GetIncrementalGroupMemberReq, resp *group.GetIncrementalGroupMemberResp) bool {
	return resp != nil && req.VersionID != "" && req.Version > 0 &&
		req.VersionID == resp.VersionID && req.Version == resp.Version &&
		!resp.Full && resp.Group == nil && resp.SortVersion == 0 &&
		len(resp.Insert) == 0 && len(resp.Update) == 0 && len(resp.Delete) == 0
}
