package groupnotices

import (
	"github.com/gin-gonic/gin"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"time"
)

// Import only this authenticated account's previous local dismissal identities.
// Every batch is retryable; it cannot change applications or other accounts.
func (h *Handler) Migrate(c *gin.Context) {
	owner, ok := h.owner(c)
	if !ok {
		return
	}
	var req struct {
		Through int64 `json:"through"`
		Items   []struct {
			Group string `json:"groupID"`
			User  string `json:"userID"`
			Time  int64  `json:"reqTime"`
		} `json:"items"`
	}
	if e := c.ShouldBindJSON(&req); e != nil || len(req.Items) > 100 || req.Through < 0 || req.Through > time.Now().UnixMilli() {
		failure(c, errs.ErrArgs.WrapMsg("invalid migration"))
		return
	}
	writes := []mongo.WriteModel{}
	for _, r := range req.Items {
		if r.Group == "" || r.User == "" || len(r.Group) > 512 || len(r.User) > 512 || r.Time <= 0 {
			failure(c, errs.ErrArgs.WrapMsg("invalid notice identity"))
			return
		}
		key := bson.M{"owner": owner, "group_id": r.Group, "user_id": r.User, "req_time": time.UnixMilli(r.Time)}
		writes = append(writes, mongo.NewUpdateOneModel().SetFilter(key).SetUpdate(bson.M{"$setOnInsert": key}).SetUpsert(true))
	}
	if len(writes) > 0 {
		if _, e := h.DB.Collection(dismissals).BulkWrite(c, writes); e != nil {
			failure(c, e)
			return
		}
	}
	update := bson.M{"$max": bson.M{"cleared_through": req.Through}, "$inc": bson.M{"revision": 1}}
	_, e := h.DB.Collection(states).UpdateOne(c, bson.M{"_id": owner}, update, options.Update().SetUpsert(true))
	if mongo.IsDuplicateKeyError(e) {
		_, e = h.DB.Collection(states).UpdateOne(c, bson.M{"_id": owner}, update)
	}
	if e != nil {
		failure(c, e)
		return
	}
	apiresp.GinSuccess(c, gin.H{})
}
