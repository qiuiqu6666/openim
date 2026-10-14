package groupnotices

import (
	"context"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/model"
	"github.com/openimsdk/protocol/constant"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"time"
)

type Handler struct{ DB *mongo.Database }

func Register(r gin.IRoutes, db *mongo.Database) {
	h := &Handler{DB: db}
	r.POST("/group/notices/list", h.List)
	r.POST("/group/notices/state", h.Status)
	r.POST("/group/notices/clear", h.Clear)
	r.POST("/group/notices/delete", h.Delete)
	r.POST("/group/notices/read", h.Read)
	r.POST("/group/notices/migrate", h.Migrate)
	r.POST("/group/notices/detail", h.Detail)
}
func (h *Handler) owner(c *gin.Context) (string, bool) {
	owner, _ := c.Get(constant.OpUserID)
	user, _ := owner.(string)
	if user == "" {
		apiresp.GinError(c, errs.ErrArgs.WrapMsg("authenticated user required"))
		return "", false
	}
	if h.DB == nil {
		apiresp.GinError(c, fmt.Errorf("group notice storage unavailable"))
		return "", false
	}
	return user, true
}
func failure(c *gin.Context, e error) { apiresp.GinError(c, e) }
func (h *Handler) state(ctx context.Context, owner string) (State, error) {
	s := State{UserID: owner}
	e := h.DB.Collection(states).FindOne(ctx, bson.M{"_id": owner}).Decode(&s)
	if errors.Is(e, mongo.ErrNoDocuments) {
		e = nil
	}
	return s, e
}
func (h *Handler) managed(ctx context.Context, owner string) ([]string, error) {
	cur, e := h.DB.Collection("group_member").Find(ctx, bson.M{"user_id": owner, "role_level": bson.M{"$in": bson.A{constant.GroupOwner, constant.GroupAdmin}}}, options.Find().SetProjection(bson.M{"group_id": 1}))
	if e != nil {
		return nil, e
	}
	defer cur.Close(ctx)
	groups := []string{}
	for cur.Next(ctx) {
		var m struct {
			ID string `bson:"group_id"`
		}
		if e = cur.Decode(&m); e != nil {
			return nil, e
		}
		groups = append(groups, m.ID)
	}
	return groups, cur.Err()
}
func (h *Handler) Status(c *gin.Context) {
	owner, ok := h.owner(c)
	if !ok {
		return
	}
	s, e := h.state(c, owner)
	if e != nil {
		failure(c, e)
		return
	}
	var req struct {
		IncludeUnread *bool `json:"includeUnread"`
	}
	if e := c.ShouldBindJSON(&req); e != nil {
		failure(c, errs.ErrArgs.WrapMsg("invalid request"))
		return
	}
	if req.IncludeUnread != nil && !*req.IncludeUnread {
		apiresp.GinSuccess(c, s)
		return
	}
	groups, e := h.managed(c, owner)
	if e != nil {
		failure(c, e)
		return
	}
	cur, e := h.DB.Collection("group_request").Aggregate(c, pipeline(owner, visibility(owner, groups, s, time.Now().UnixMilli(), nil, true), 0, true), options.Aggregate().SetMaxTime(5*time.Second))
	if e != nil {
		failure(c, e)
		return
	}
	defer cur.Close(c)
	var result []struct {
		Count int64 `bson:"count"`
	}
	if e = cur.All(c, &result); e != nil {
		failure(c, e)
		return
	}
	count := int64(0)
	if len(result) > 0 {
		count = result[0].Count
	}
	apiresp.GinSuccess(c, gin.H{"revision": s.Revision, "clearedThrough": s.ClearedThrough, "readThrough": s.ReadThrough, "unreadCount": count})
}
func (h *Handler) List(c *gin.Context) {
	owner, ok := h.owner(c)
	if !ok {
		return
	}
	var req struct {
		Cursor string `json:"cursor"`
		Limit  int    `json:"limit"`
	}
	if e := c.ShouldBindJSON(&req); e != nil {
		failure(c, errs.ErrArgs.WrapMsg("invalid request"))
		return
	}
	if req.Limit == 0 {
		req.Limit = 20
	}
	if req.Limit < 1 || req.Limit > 100 {
		failure(c, errs.ErrArgs.WrapMsg("limit must be 1..100"))
		return
	}
	s, e := h.state(c, owner)
	if e != nil {
		failure(c, e)
		return
	}
	now := time.Now().UnixMilli()
	snapshot := now
	var cursor *Cursor
	if req.Cursor != "" {
		v, e := decodeCursor(req.Cursor, owner, now)
		if e != nil {
			failure(c, errs.ErrArgs.WrapMsg("invalid cursor"))
			return
		}
		if v.Revision != s.Revision {
			apiresp.GinSuccess(c, gin.H{"reset": true})
			return
		}
		snapshot = v.Snapshot
		cursor = &v
	}
	groups, e := h.managed(c, owner)
	if e != nil {
		failure(c, e)
		return
	}
	cur, e := h.DB.Collection("group_request").Aggregate(c, pipeline(owner, visibility(owner, groups, s, snapshot, cursor, false), req.Limit, false), options.Aggregate().SetMaxTime(5*time.Second))
	if e != nil {
		failure(c, e)
		return
	}
	defer cur.Close(c)
	rows := []model.GroupRequest{}
	if e = cur.All(c, &rows); e != nil {
		failure(c, e)
		return
	}
	next := ""
	if len(rows) > req.Limit {
		rows = rows[:req.Limit]
		last := rows[len(rows)-1]
		next = (Cursor{owner, snapshot, s.Revision, last.ReqTime.UnixMilli(), last.GroupID, last.UserID}).encode()
	}
	items, e := h.present(c, rows)
	if e != nil {
		failure(c, e)
		return
	}
	latest, e := h.state(c, owner)
	if e != nil {
		failure(c, e)
		return
	}
	if latest.Revision != s.Revision {
		apiresp.GinSuccess(c, gin.H{"reset": true})
		return
	}
	apiresp.GinSuccess(c, gin.H{"items": items, "nextCursor": next, "snapshotTime": snapshot, "revision": s.Revision, "reset": false})
}
func (h *Handler) boundary(c *gin.Context, field string, revision bool) {
	owner, ok := h.owner(c)
	if !ok {
		return
	}
	var req struct {
		Through int64 `json:"through"`
	}
	if e := c.ShouldBindJSON(&req); e != nil || req.Through <= 0 || req.Through > time.Now().UnixMilli() {
		failure(c, errs.ErrArgs.WrapMsg("invalid snapshot time"))
		return
	}
	update := bson.M{"$max": bson.M{field: req.Through}}
	if revision {
		update["$inc"] = bson.M{"revision": 1}
	}
	var s State
	e := h.DB.Collection(states).FindOneAndUpdate(c, bson.M{"_id": owner}, update, options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After)).Decode(&s)
	if mongo.IsDuplicateKeyError(e) {
		e = h.DB.Collection(states).FindOneAndUpdate(c, bson.M{"_id": owner}, update, options.FindOneAndUpdate().SetReturnDocument(options.After)).Decode(&s)
	}
	if e != nil {
		failure(c, e)
		return
	}
	apiresp.GinSuccess(c, s)
}
func (h *Handler) Clear(c *gin.Context) { h.boundary(c, "cleared_through", true) }
func (h *Handler) Read(c *gin.Context)  { h.boundary(c, "read_through", false) }
func (h *Handler) Delete(c *gin.Context) {
	owner, ok := h.owner(c)
	if !ok {
		return
	}
	var req struct {
		Group string `json:"groupID"`
		User  string `json:"userID"`
		Time  int64  `json:"reqTime"`
	}
	if e := c.ShouldBindJSON(&req); e != nil || req.Group == "" || req.User == "" || len(req.Group) > 512 || len(req.User) > 512 || req.Time <= 0 {
		failure(c, errs.ErrArgs.WrapMsg("invalid notice"))
		return
	}
	// A dismissal belongs only to the authenticated account, never to the group.
	key := bson.M{"owner": owner, "group_id": req.Group, "user_id": req.User, "req_time": time.UnixMilli(req.Time)}
	_, e := h.DB.Collection(dismissals).UpdateOne(c, key, bson.M{"$setOnInsert": key}, options.Update().SetUpsert(true))
	if e != nil && !mongo.IsDuplicateKeyError(e) {
		failure(c, e)
		return
	}
	_, e = h.DB.Collection(states).UpdateOne(c, bson.M{"_id": owner}, bson.M{"$inc": bson.M{"revision": 1}}, options.Update().SetUpsert(true))
	if mongo.IsDuplicateKeyError(e) {
		_, e = h.DB.Collection(states).UpdateOne(c, bson.M{"_id": owner}, bson.M{"$inc": bson.M{"revision": 1}})
	}
	if e != nil {
		failure(c, e)
		return
	}
	apiresp.GinSuccess(c, gin.H{})
}
