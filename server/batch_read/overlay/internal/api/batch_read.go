package api

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/openimsdk/open-im-server/v3/internal/api/batchread"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/mcontext"
)

func batchReadHandler(service *batchread.Service, prepare bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		user := mcontext.GetOpUserID(c)
		if user == "" {
			apiresp.GinError(c, errs.ErrNoPermission.WrapMsg("authentication required"))
			return
		}
		var req struct {
			Scope           string             `json:"scope"`
			ConversationIDs []string           `json:"conversationIDs"`
			Targets         []batchread.Target `json:"targets"`
		}
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 256<<10)
		if err := c.ShouldBindJSON(&req); err != nil {
			apiresp.GinError(c, errs.ErrArgs.WrapMsg("invalid batch read request"))
			return
		}
		ctx, cancel := context.WithTimeout(c, 20*time.Second)
		defer cancel()
		stop := context.AfterFunc(c.Request.Context(), cancel)
		defer stop()
		if prepare {
			targets, err := service.Prepare(ctx, user, req.Scope, req.ConversationIDs)
			if err != nil {
				apiresp.GinError(c, err)
				return
			}
			apiresp.GinSuccess(c, gin.H{"targets": targets, "batchSize": batchread.BatchSize})
		} else {
			results, err := service.Apply(ctx, user, req.Targets)
			if err != nil {
				apiresp.GinError(c, err)
				return
			}
			apiresp.GinSuccess(c, gin.H{"results": results})
		}
	}
}
