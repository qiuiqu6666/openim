package group

import (
	"context"
	"sort"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/syncer"
	"github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/utils/datautil"
)

//func (g *Group) GetIncrementalGroupMemberBatch(ctx context.Context, groups []*group.GetIncrementalGroupMemberReq) (map[string]*group.GetIncrementalGroupMemberResp, error) {
//	resp, err := g.getIncrementalGroupMemberBatch(ctx, &group.BatchGetIncrementalGroupMemberReq{UserID: g.loginUserID, ReqList: groups})
//	if err != nil {
//		return nil, err
//	}
//	return resp.RespList, nil
//}

func (g *Group) groupAndMemberVersionTableName() string {
	return "local_group_entities_version"
}

func (g *Group) groupTableName() string {
	return model_struct.LocalGroup{}.TableName()
}

func (g *Group) SyncAllJoinedGroupsAndMembersWithLock(ctx context.Context) error {
	if err := g.groupSyncMutex.LockContext(ctx); err != nil {
		return err
	}
	defer g.groupSyncMutex.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	groupIDs, err := g.IncrSyncJoinGroupAndGetIDs(ctx)
	if err != nil {
		return err
	}
	return g.IncrSyncJoinGroupMember(ctx, groupIDs...)
}

func (g *Group) IncrSyncJoinGroupMember(ctx context.Context, groupIDs ...string) error {
	if len(groupIDs) == 0 {
		groups, err := g.db.GetJoinedGroupListDB(ctx)
		if err != nil {
			return err
		}
		groupIDs = datautil.Slice(groups, func(e *model_struct.LocalGroup) string {
			return e.GroupID
		})
	}
	return g.IncrSyncGroupAndMember(ctx, groupIDs...)
}

func (g *Group) IncrSyncGroupAndMember(ctx context.Context, groupIDs ...string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if len(groupIDs) == 0 {
		return nil
	}
	const maxSyncNum = 20
	const scope = "group-members"
	// Stable ordering prevents a cancelled prefix from being randomly retried.
	groupIDSet := datautil.SliceSet(groupIDs)
	ids := make([]string, 0, len(groupIDSet))
	for id := range groupIDSet {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	ids = common.PendingMetadataItems(ctx, scope, ids)
	for start := 0; start < len(ids); start += maxSyncNum {
		end := start + maxSyncNum
		if end > len(ids) {
			end = len(ids)
		}
		if err := g.syncMemberBatch(ctx, scope, ids[start:end]); err != nil {
			return err
		}
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	common.FinishMetadataItems(ctx, scope)
	return nil
}

func (g *Group) syncMemberBatch(ctx context.Context, scope string, ids []string) error {
	finish := common.BeginMetadataBatch(ctx)
	defer finish()
	groups := make([]*group.GetIncrementalGroupMemberReq, 0, len(ids))
	for _, id := range ids {
		if err := ctx.Err(); err != nil {
			return err
		}
		req := &group.GetIncrementalGroupMemberReq{GroupID: id}
		lvs, err := g.db.GetVersionSync(ctx, g.groupAndMemberVersionTableName(), id)
		if err == nil {
			req.VersionID, req.Version = lvs.VersionID, lvs.Version
		} else if !errs.ErrRecordNotFound.Is(err) {
			return err
		}
		groups = append(groups, req)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	responses, err := g.getIncrementalGroupMemberBatch(ctx, groups)
	if err != nil {
		return err
	}
	tasks := make([]func() error, 0, len(groups))
	for _, req := range groups {
		id := req.GroupID
		resp, present := responses[id]
		if !present {
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
	return runGroupSyncBatch(ctx, tasks)
}

func (g *Group) syncGroupAndMember(ctx context.Context, groupID string, resp *group.GetIncrementalGroupMemberResp) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	groupMemberSyncer := syncer.VersionSynchronizer[*model_struct.LocalGroupMember, *group.GetIncrementalGroupMemberResp]{
		Ctx:       ctx,
		DB:        g.db,
		TableName: g.groupAndMemberVersionTableName(),
		EntityID:  groupID,
		Key: func(localGroupMember *model_struct.LocalGroupMember) string {
			return localGroupMember.UserID
		},
		Local: func() ([]*model_struct.LocalGroupMember, error) {
			return g.db.GetGroupMemberListByGroupID(ctx, groupID)
		},
		ServerVersion: func() *group.GetIncrementalGroupMemberResp {
			return resp
		},
		Full: func(resp *group.GetIncrementalGroupMemberResp) bool {
			return resp.Full
		},
		Version: func(resp *group.GetIncrementalGroupMemberResp) (string, uint64) {
			return resp.VersionID, resp.Version
		},
		Delete: func(resp *group.GetIncrementalGroupMemberResp) []string {
			return resp.Delete
		},
		Update: func(resp *group.GetIncrementalGroupMemberResp) []*model_struct.LocalGroupMember {
			return datautil.Batch(ServerGroupMemberToLocalGroupMember, resp.Update)
		},
		Insert: func(resp *group.GetIncrementalGroupMemberResp) []*model_struct.LocalGroupMember {
			return datautil.Batch(ServerGroupMemberToLocalGroupMember, resp.Insert)
		},
		ExtraData: func(resp *group.GetIncrementalGroupMemberResp) any {
			return resp.Group
		},
		ExtraDataProcessor: func(ctx context.Context, data any) error {
			groupInfo, ok := data.(*sdkws.GroupInfo)
			if !ok {
				return errs.New("group info type error")
			}
			if groupInfo == nil {
				return nil
			}
			return g.syncGroupProfile(ctx, groupID, groupInfo)
		},
		Syncer: func(server, local []*model_struct.LocalGroupMember) error {
			return g.groupMemberSyncer.Sync(ctx, server, local, nil)
		},
		FullSyncer: func(ctx context.Context) error {
			return g.syncFullGroupMembers(ctx, groupID)
		},
		FullID: func(ctx context.Context) ([]string, error) {
			resp, err := g.getFullGroupMemberUserIDs(ctx, &group.GetFullGroupMemberUserIDsReq{
				GroupID: groupID,
			})
			if err != nil {
				return nil, err
			}
			return resp.UserIDs, nil
		},
		IDOrderChanged: func(resp *group.GetIncrementalGroupMemberResp) bool {
			if resp.SortVersion > 0 {
				return true
			}
			return false
		},
	}
	return groupMemberSyncer.IncrementalSync()
}

func (g *Group) onlineSyncGroupAndMember(ctx context.Context, groupID string, deleteGroupMembers, updateGroupMembers, insertGroupMembers []*sdkws.GroupMemberFullInfo,
	updateGroup *sdkws.GroupInfo, sortVersion uint64, version uint64, versionID string) error {
	groupMemberSyncer := syncer.VersionSynchronizer[*model_struct.LocalGroupMember, *group.GetIncrementalGroupMemberResp]{
		Ctx:       ctx,
		DB:        g.db,
		TableName: g.groupAndMemberVersionTableName(),
		EntityID:  groupID,
		Key: func(localGroupMember *model_struct.LocalGroupMember) string {
			return localGroupMember.UserID
		},
		Local: func() ([]*model_struct.LocalGroupMember, error) {
			return g.db.GetGroupMemberListByGroupID(ctx, groupID)
		},
		ServerVersion: func() *group.GetIncrementalGroupMemberResp {
			return &group.GetIncrementalGroupMemberResp{
				Version:   version,
				VersionID: versionID,
				Full:      false,
				Delete: datautil.Slice(deleteGroupMembers, func(e *sdkws.GroupMemberFullInfo) string {
					return e.UserID
				}),
				Insert:      insertGroupMembers,
				Update:      updateGroupMembers,
				Group:       updateGroup,
				SortVersion: sortVersion,
			}
		},
		Server: func(version *model_struct.LocalVersionSync) (*group.GetIncrementalGroupMemberResp, error) {
			singleGroupReq := &group.GetIncrementalGroupMemberReq{
				GroupID:   groupID,
				VersionID: version.VersionID,
				Version:   version.Version,
			}

			resp, err := g.getIncrementalGroupMemberBatch(ctx, []*group.GetIncrementalGroupMemberReq{singleGroupReq})
			if err != nil {
				return nil, err
			}
			if resp != nil {
				if singleGroupResp, ok := resp[groupID]; ok {
					return singleGroupResp, nil
				}
			}
			return nil, errs.New("group member version record not found")

		},
		Full: func(resp *group.GetIncrementalGroupMemberResp) bool {
			return resp.Full
		},
		Version: func(resp *group.GetIncrementalGroupMemberResp) (string, uint64) {
			return resp.VersionID, resp.Version
		},
		Delete: func(resp *group.GetIncrementalGroupMemberResp) []string {
			return resp.Delete
		},
		Update: func(resp *group.GetIncrementalGroupMemberResp) []*model_struct.LocalGroupMember {
			return datautil.Batch(ServerGroupMemberToLocalGroupMember, resp.Update)
		},
		Insert: func(resp *group.GetIncrementalGroupMemberResp) []*model_struct.LocalGroupMember {
			return datautil.Batch(ServerGroupMemberToLocalGroupMember, resp.Insert)
		},
		ExtraData: func(resp *group.GetIncrementalGroupMemberResp) any {
			return resp.Group
		},
		ExtraDataProcessor: func(ctx context.Context, data any) error {
			groupInfo, ok := data.(*sdkws.GroupInfo)
			if !ok {
				return errs.New("group info type error")
			}
			if groupInfo == nil {
				return nil
			}
			return g.syncGroupProfile(ctx, groupID, groupInfo)
		},
		Syncer: func(server, local []*model_struct.LocalGroupMember) error {
			return g.groupMemberSyncer.Sync(ctx, server, local, nil)
		},
		FullSyncer: func(ctx context.Context) error {
			return g.syncFullGroupMembers(ctx, groupID)
		},
		FullID: func(ctx context.Context) ([]string, error) {
			resp, err := g.getFullGroupMemberUserIDs(ctx, &group.GetFullGroupMemberUserIDsReq{
				GroupID: groupID,
			})
			if err != nil {
				return nil, err
			}
			return resp.UserIDs, nil
		},
		IDOrderChanged: func(resp *group.GetIncrementalGroupMemberResp) bool {
			if resp.SortVersion > 0 {
				return true
			}
			return false
		},
	}
	return groupMemberSyncer.CheckVersionSync()
}

func (g *Group) IncrSyncJoinGroup(ctx context.Context) error {
	_, err := g.IncrSyncJoinGroupAndGetIDs(ctx)
	return err
}

func (g *Group) IncrSyncJoinGroupAndGetIDs(ctx context.Context) ([]string, error) {
	joinedGroupSyncer := syncer.VersionSynchronizer[*model_struct.LocalGroup, *group.GetIncrementalJoinGroupResp]{
		Ctx:       ctx,
		DB:        g.db,
		TableName: g.groupTableName(),
		EntityID:  g.loginUserID,
		Key: func(LocalGroup *model_struct.LocalGroup) string {
			return LocalGroup.GroupID
		},
		Local: func() ([]*model_struct.LocalGroup, error) {
			return g.db.GetJoinedGroupListDB(ctx)
		},
		Server: func(version *model_struct.LocalVersionSync) (*group.GetIncrementalJoinGroupResp, error) {
			return g.getIncrementalJoinGroup(ctx, &group.GetIncrementalJoinGroupReq{
				UserID:    g.loginUserID,
				Version:   version.Version,
				VersionID: version.VersionID,
			})
		},
		Full: func(resp *group.GetIncrementalJoinGroupResp) bool {
			return resp.Full
		},
		Version: func(resp *group.GetIncrementalJoinGroupResp) (string, uint64) {
			return resp.VersionID, resp.Version
		},
		Delete: func(resp *group.GetIncrementalJoinGroupResp) []string {
			return resp.Delete
		},
		Update: func(resp *group.GetIncrementalJoinGroupResp) []*model_struct.LocalGroup {
			return datautil.Batch(ServerGroupToLocalGroup, resp.Update)
		},
		Insert: func(resp *group.GetIncrementalJoinGroupResp) []*model_struct.LocalGroup {
			return datautil.Batch(ServerGroupToLocalGroup, resp.Insert)
		},
		Syncer: func(server, local []*model_struct.LocalGroup) error {
			return g.groupSyncer.Sync(ctx, server, local, nil)
		},
		FullSyncer: func(ctx context.Context) error {
			// Fetch all pages before touching local rows. Differential application
			// preserves group callbacks, conversation profile updates and retries.
			server, err := g.getServerJoinGroup(ctx)
			if err != nil {
				return err
			}
			local, err := g.db.GetJoinedGroupListDB(ctx)
			if err != nil {
				return err
			}
			return g.groupSyncer.Sync(ctx, datautil.Batch(ServerGroupToLocalGroup, server), local, nil)
		},
		FullID: func(ctx context.Context) ([]string, error) {
			resp, err := g.getFullJoinGroupIDs(ctx, &group.GetFullJoinGroupIDsReq{
				UserID: g.loginUserID,
			})
			if err != nil {
				return nil, err
			}
			return resp.GroupIDs, nil

		},
		IDOrderChanged: func(resp *group.GetIncrementalJoinGroupResp) bool {
			if resp.SortVersion > 0 {
				return true
			}
			return false
		},
	}
	if err := joinedGroupSyncer.IncrementalSync(); err != nil {
		return nil, err
	}
	lvs, err := g.db.GetVersionSync(ctx, g.groupTableName(), g.loginUserID)
	if err != nil && !errs.ErrRecordNotFound.Is(err) {
		return nil, err
	}
	return lvs.UIDList, nil
}
