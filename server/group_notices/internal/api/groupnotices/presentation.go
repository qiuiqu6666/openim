package groupnotices

import (
	"context"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/model"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// Fetch only public fields for the bounded page, never every managed group.
func (h *Handler) present(ctx context.Context, rows []model.GroupRequest) ([]bson.M, error) {
	result := []bson.M{}
	if len(rows) == 0 {
		return result, nil
	}
	gids := []string{}
	uids := []string{}
	for _, r := range rows {
		gids = append(gids, r.GroupID)
		uids = append(uids, r.UserID, r.InviterUserID, r.HandleUserID)
	}
	gc, e := h.DB.Collection("group").Find(ctx, bson.M{"group_id": bson.M{"$in": gids}}, options.Find().SetProjection(bson.M{"group_id": 1, "group_name": 1, "face_url": 1}))
	if e != nil {
		return nil, e
	}
	defer gc.Close(ctx)
	var groups []model.Group
	if e = gc.All(ctx, &groups); e != nil {
		return nil, e
	}
	gm := map[string]model.Group{}
	for _, g := range groups {
		gm[g.GroupID] = g
	}
	uc, e := h.DB.Collection("user").Find(ctx, bson.M{"user_id": bson.M{"$in": uids}}, options.Find().SetProjection(bson.M{"user_id": 1, "nickname": 1, "face_url": 1}))
	if e != nil {
		return nil, e
	}
	defer uc.Close(ctx)
	var users []model.User
	if e = uc.All(ctx, &users); e != nil {
		return nil, e
	}
	um := map[string]model.User{}
	for _, u := range users {
		um[u.UserID] = u
	}
	for _, r := range rows {
		handled := int64(0)
		if !r.HandledTime.IsZero() {
			handled = r.HandledTime.UnixMilli()
		}
		result = append(result, bson.M{"groupID": r.GroupID, "groupName": gm[r.GroupID].GroupName, "groupFaceURL": gm[r.GroupID].FaceURL, "userID": r.UserID, "nickname": um[r.UserID].Nickname, "userFaceURL": um[r.UserID].FaceURL, "reqTime": r.ReqTime.UnixMilli(), "reqMsg": r.ReqMsg, "handleResult": r.HandleResult, "handleMsg": r.HandledMsg, "handleUserID": r.HandleUserID, "handledTime": handled, "joinSource": r.JoinSource, "inviterUserID": r.InviterUserID, "ex": r.Ex, "handlerNickname": um[r.HandleUserID].Nickname, "inviterNickname": um[r.InviterUserID].Nickname})
	}
	return result, nil
}
