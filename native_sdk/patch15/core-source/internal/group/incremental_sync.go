package group

import (
	"context"
	"sync"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/syncer"
	constantpb "github.com/openimsdk/protocol/constant"
	"github.com/openimsdk/protocol/group"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/log"
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
	g.groupSyncMutex.Lock()
	defer g.groupSyncMutex.Unlock()
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
	var wg sync.WaitGroup
	if len(groupIDs) == 0 {
		return nil
	}
	const maxSyncNum = constantpb.MaxSyncPullNumber
	groupIDSet := datautil.SliceSet(groupIDs)
	var groups []*group.GetIncrementalGroupMemberReq
	if len(groupIDs) > maxSyncNum {
		groups = make([]*group.GetIncrementalGroupMemberReq, 0, maxSyncNum)
	} else {
		groups = make([]*group.GetIncrementalGroupMemberReq, 0, len(groupIDs))
	}
	for {
		if len(groupIDSet) == 0 {
			return nil
		}
		for groupID := range groupIDSet {
			if len(groups) == cap(groups) {
				break
			}
			req := group.GetIncrementalGroupMemberReq{
				GroupID: groupID,
			}

			lvs, err := g.db.GetVersionSync(ctx, g.groupAndMemberVersionTableName(), groupID)
			if err == nil {
				req.VersionID = lvs.VersionID
				req.Version = lvs.Version
			} else if !errs.ErrRecordNotFound.Is(err) {
				return err
			}
			groups = append(groups, &req)
		}
		groupVersion, err := g.getIncrementalGroupMemberBatch(ctx, groups)
		if err != nil {
			return err
		}
		// Unchanged groups may be omitted by the batch endpoint. Retire the
		// requested batch together and reset it even when the response is empty.
		results := make(chan error, len(groups))
		requested := make(map[string]bool, len(groups))
		for _, req := range groups {
			requested[req.GroupID] = true
			delete(groupIDSet, req.GroupID)
		}
		groups = groups[:0]
		for groupID, resp := range groupVersion {
			if !requested[groupID] {
				continue
			}
			if resp == nil {
				results <- errs.New("nil incremental group response", "groupID", groupID)
				continue
			}
			tempResp := resp
			tempGroupID := groupID
			wg.Add(1)
			go func() {
				defer wg.Done()
				err := g.syncGroupAndMember(ctx, tempGroupID, tempResp)
				if err != nil {
					log.ZError(ctx, "sync Group And Member error", errs.Wrap(err))
				}
				results <- err
			}()
			delete(groupIDSet, tempGroupID)
		}
		wg.Wait()
		close(results)
		for err := range results {
			if err != nil {
				return err
			}
		}
	}
}

func (g *Group) syncGroupAndMember(ctx context.Context, groupID string, resp *group.GetIncrementalGroupMemberResp) error {
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
