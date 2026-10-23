package group

import (
	"context"
	"fmt"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/api"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	protocol "github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/log"
	"github.com/openimsdk/tools/utils/datautil"
)

type joinedGroupVersion struct {
	id                   string
	version, sortVersion uint64
}

type joinedGroupSnapshot struct {
	gate     groupSyncGate
	version  joinedGroupVersion
	groups   []*sdkws.GroupInfo
	nextPage int32
	complete bool
	ids      []string
}

func (s *joinedGroupSnapshot) reset(version joinedGroupVersion) {
	s.version, s.groups, s.nextPage, s.complete, s.ids = version, nil, 1, false, nil
}

func joinedVersion(resp *protocol.GetIncrementalJoinGroupResp) joinedGroupVersion {
	return joinedGroupVersion{resp.VersionID, resp.Version, resp.SortVersion}
}

// No local row is removed until every page, the authoritative ID set and the
// version agree. Pages are staged in the obligation so cancellation only costs
// the in-flight page. Its caller holds s.gate through version persistence.
func (g *Group) syncJoinedGroupSnapshot(ctx context.Context, s *joinedGroupSnapshot, version joinedGroupVersion) error {
	if s.nextPage == 0 || s.version != version {
		s.reset(version)
	}
	const pageSize = 200
	for !s.complete {
		if err := ctx.Err(); err != nil {
			return err
		}
		page := s.nextPage
		resp, err := api.GetJoinedGroupList.Invoke(ctx, &protocol.GetJoinedGroupListReq{
			FromUserID: g.loginUserID,
			Pagination: &sdkws.RequestPagination{PageNumber: page, ShowNumber: pageSize},
		})
		if err != nil {
			log.ZWarn(ctx, "joined group snapshot page deferred", err, "page", page, "retainedGroups", len(s.groups))
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		s.groups = append(s.groups, resp.Groups...)
		s.nextPage++
		s.complete = len(resp.Groups) < pageSize
		common.RecordMetadataCheckpoint(ctx)
		log.ZInfo(ctx, "joined group snapshot page retained", "page", page, "retainedGroups", len(s.groups), "complete", s.complete)
	}
	// Fetch IDs before applying the snapshot, not after deleting local rows.
	if s.ids == nil {
		ids, err := g.getFullJoinGroupIDs(ctx, &protocol.GetFullJoinGroupIDsReq{UserID: g.loginUserID})
		if err != nil {
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		s.ids = append([]string{}, ids.GroupIDs...)
		common.RecordMetadataCheckpoint(ctx)
	}
	current, err := g.getIncrementalJoinGroup(ctx, &protocol.GetIncrementalJoinGroupReq{
		UserID: g.loginUserID, VersionID: version.id, Version: version.version,
	})
	if err != nil {
		return err
	}
	// SortVersion may be zero on an unchanged incremental response.
	if current.VersionID != version.id || current.Version != version.version ||
		(current.SortVersion != 0 && current.SortVersion != version.sortVersion) || !joinedSnapshotMatchesIDs(s.groups, s.ids) {
		s.reset(joinedVersion(current))
		return fmt.Errorf("joined group snapshot changed during pagination; retry required")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	local, err := g.db.GetJoinedGroupListDB(ctx)
	if err != nil {
		return err
	}
	if err := g.groupSyncer.Sync(ctx, datautil.Batch(ServerGroupToLocalGroup, s.groups), local, nil); err != nil {
		return err
	}
	return nil
}

func joinedSnapshotMatchesIDs(groups []*sdkws.GroupInfo, ids []string) bool {
	if len(groups) != len(ids) {
		return false
	}
	seen := make(map[string]bool, len(groups))
	for _, group := range groups {
		if group == nil || group.GroupID == "" || seen[group.GroupID] {
			return false
		}
		seen[group.GroupID] = true
	}
	for _, id := range ids {
		if !seen[id] {
			return false
		}
		delete(seen, id)
	}
	return len(seen) == 0
}
