package groupnotices

import (
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/model"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"time"
)

// A retained review page can recheck one record without reloading older pages.
func (h *Handler) Detail(c *gin.Context) {
	owner, ok := h.owner(c)
	if !ok {
		return
	}
	var req struct {
		Group string `json:"groupID"`
		User  string `json:"userID"`
		Time  int64  `json:"reqTime"`
	}
	if e := c.ShouldBindJSON(&req); e != nil || req.Group == "" || req.User == "" || req.Time <= 0 {
		failure(c, errs.ErrArgs.WrapMsg("invalid notice"))
		return
	}
	groups, e := h.managed(c, owner)
	if e != nil {
		failure(c, e)
		return
	}
	filter := bson.M{"group_id": req.Group, "user_id": req.User, "req_time": time.UnixMilli(req.Time), "$or": bson.A{bson.M{"user_id": owner}, bson.M{"group_id": bson.M{"$in": groups}}}}
	var row model.GroupRequest
	e = h.DB.Collection("group_request").FindOne(c, filter).Decode(&row)
	if errors.Is(e, mongo.ErrNoDocuments) {
		apiresp.GinSuccess(c, gin.H{"item": nil})
		return
	}
	if e != nil {
		failure(c, e)
		return
	}
	items, e := h.present(c, []model.GroupRequest{row})
	if e != nil {
		failure(c, e)
		return
	}
	apiresp.GinSuccess(c, gin.H{"item": items[0]})
}
