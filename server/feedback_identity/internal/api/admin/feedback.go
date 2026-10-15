package admin

import (
	"github.com/gin-gonic/gin"
	"github.com/openimsdk/chat/pkg/protocol/chat"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
)

func (o *Api) SearchFeedback(c *gin.Context) {
	var req chat.AdminSearchFeedbackReq
	if err := c.ShouldBindJSON(&req); err != nil {
		apiresp.GinError(c, errs.ErrArgs.WrapMsg(err.Error()))
		return
	}
	resp, err := o.chatClient.AdminSearchFeedback(c, &req)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	data, err := o.feedbackWithNicknames(c, resp)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	apiresp.GinSuccess(c, data)
}

func (o *Api) FeedbackAdminDetail(c *gin.Context) {
	var req chat.AdminFeedbackDetailReq
	if err := c.ShouldBindJSON(&req); err != nil {
		apiresp.GinError(c, errs.ErrArgs.WrapMsg(err.Error()))
		return
	}
	resp, err := o.chatClient.AdminFeedbackDetail(c, &req)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	data, err := o.feedbackWithNicknames(c, resp)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	apiresp.GinSuccess(c, data)
}

func (o *Api) UpdateFeedback(c *gin.Context) {
	var req chat.AdminUpdateFeedbackReq
	if err := c.ShouldBindJSON(&req); err != nil {
		apiresp.GinError(c, errs.ErrArgs.WrapMsg(err.Error()))
		return
	}
	resp, err := o.chatClient.AdminUpdateFeedback(c, &req)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	apiresp.GinSuccess(c, resp)
}

func (o *Api) FeedbackLogURL(c *gin.Context) {
	var req chat.AdminFeedbackLogURLReq
	if err := c.ShouldBindJSON(&req); err != nil {
		apiresp.GinError(c, errs.ErrArgs.WrapMsg(err.Error()))
		return
	}
	resp, err := o.chatClient.AdminFeedbackLogURL(c, &req)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	apiresp.GinSuccess(c, resp)
}
