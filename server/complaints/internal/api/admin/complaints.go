package admin

import (
	"context"
	"github.com/gin-gonic/gin"
	"github.com/openimsdk/chat/pkg/common/config"
	table "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/imapi"
	"github.com/openimsdk/chat/pkg/common/mctx"
	"github.com/openimsdk/chat/pkg/common/stickermedia"
	"github.com/openimsdk/chat/pkg/complaints"
	"github.com/openimsdk/protocol/user"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/bson"
)

func (o *Api) initComplaints(ctx context.Context, cfg *config.AllConfig) error {
	store, err := complaints.New(ctx, o.identityDB)
	if err != nil {
		return err
	}
	mc := cfg.Chat.Sticker.Minio
	signer, err := stickermedia.NewMinioStore(nil, mc)
	if err != nil {
		return err
	}
	o.complaints = &complaints.API{Store: store, Media: signer, Enrich: func(ctx context.Context, rows []*complaints.Record) error {
		return o.enrichComplaints(ctx, rows, cfg.Share.OpenIM.ApiURL)
	}}
	return nil
}
func (o *Api) SearchComplaints(c *gin.Context) { o.complaints.Search(c) }
func (o *Api) ComplaintDetail(c *gin.Context)  { o.complaints.Detail(c) }
func (o *Api) UpdateComplaint(c *gin.Context) {
	p := currentAdmin(c)
	if p == nil {
		apiresp.GinError(c, errs.ErrNoPermission)
		return
	}
	o.complaints.Update(c, p.ID)
}

func (o *Api) ComplaintScreenshot(c *gin.Context) { o.complaints.Screenshot(c) }

// Resolve current names in batches for the visible page; historical records also benefit.
func (o *Api) enrichComplaints(ctx context.Context, rows []*complaints.Record, imURL string) error {
	users, groups := map[string]bool{}, map[string]bool{}
	for _, r := range rows {
		if r.UserID != "" {
			users[r.UserID] = true
		}
		if r.ReportedUserID != "" {
			users[r.ReportedUserID] = true
		}
		if r.GroupID != "" {
			groups[r.GroupID] = true
		}
	}
	names := map[string]string{}
	if len(users) > 0 {
		ids := make([]string, 0, len(users))
		for id := range users {
			ids = append(ids, id)
		}
		var user table.Attribute
		cur, err := o.identityDB.Collection(user.TableName()).Find(ctx, bson.M{"user_id": bson.M{"$in": ids}})
		if err != nil {
			return err
		}
		defer cur.Close(ctx)
		for cur.Next(ctx) {
			var u table.Attribute
			if err = cur.Decode(&u); err != nil {
				return err
			}
			names[u.UserID] = u.Nickname
		}
		if err = cur.Err(); err != nil {
			return err
		}
	}
	if len(users) > 0 {
		ids := make([]string, 0, len(users))
		for id := range users {
			ids = append(ids, id)
		}
		if token, err := o.imApiCaller.ImAdminTokenWithDefaultAdmin(ctx); err == nil {
			caller := imapi.NewApiCaller[user.GetDesignateUsersReq, user.GetDesignateUsersResp]("/user/get_users_info")
			if resp, err := caller.Call(mctx.WithApiToken(ctx, token), imURL, &user.GetDesignateUsersReq{UserIDs: ids}); err == nil {
				for _, u := range resp.UsersInfo {
					if u.Nickname != "" {
						names[u.UserID] = u.Nickname
					}
				}
			}
		}
	}
	groupNames := map[string]string{}
	if len(groups) > 0 {
		ids := make([]string, 0, len(groups))
		for id := range groups {
			ids = append(ids, id)
		}
		if token, err := o.imApiCaller.ImAdminTokenWithDefaultAdmin(ctx); err == nil {
			if info, err := o.imApiCaller.FindGroupInfo(mctx.WithApiToken(ctx, token), ids); err == nil {
				for _, g := range info {
					groupNames[g.GroupID] = g.GroupName
				}
			}
		}
	}
	for _, r := range rows {
		r.UserNickname = names[r.UserID]
		r.ReportedUserNickname = names[r.ReportedUserID]
		r.GroupName = groupNames[r.GroupID]
	}
	return nil
}
