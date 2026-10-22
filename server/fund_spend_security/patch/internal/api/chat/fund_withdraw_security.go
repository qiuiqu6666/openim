package chat

import (
	"github.com/gin-gonic/gin"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	"github.com/openimsdk/tools/apiresp"
	"github.com/openimsdk/tools/errs"
)

// Keep all status fields in HTTP JSON. Protobuf's omitempty drops false, zero,
// empty strings and empty reasons, which clients need to interpret the decision.
type fundWithdrawalSecurityResponse struct {
	SMSRequired   bool     `json:"smsRequired"`
	Reasons       []string `json:"reasons"`
	BlockedUntil  int64    `json:"blockedUntil"`
	PhoneMasked   string   `json:"phoneMasked"`
	Currency      string   `json:"currency"`
	SMSThreshold  string   `json:"smsThreshold"`
	CooldownHours uint32   `json:"cooldownHours"`
}

func bindFundWithdrawalSecurity(c *gin.Context) (*pb.FundWithdrawalSecurityReq, bool) {
	var req pb.FundWithdrawalSecurityReq
	if err := c.ShouldBindJSON(&req); err != nil || req.TransactionCount() != 1 {
		apiresp.GinError(c, errs.ErrArgs.WrapMsg("请提供一笔提现或转账的完整信息"))
		return nil, false
	}
	return &req, true
}

func (o *Api) GetFundWithdrawalSecurity(c *gin.Context) {
	req, ok := bindFundWithdrawalSecurity(c)
	if !ok {
		return
	}
	resp, err := o.chatClient.GetFundWithdrawalSecurity(c, req)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	if resp == nil {
		apiresp.GinError(c, errs.ErrInternalServer.WrapMsg("安全验证信息暂不可用"))
		return
	}
	reasons := resp.Reasons
	if reasons == nil {
		reasons = []string{}
	}
	apiresp.GinSuccess(c, fundWithdrawalSecurityResponse{
		SMSRequired: resp.SmsRequired, Reasons: reasons, BlockedUntil: resp.BlockedUntil,
		PhoneMasked: resp.PhoneMasked, Currency: resp.Currency,
		SMSThreshold: resp.SmsThreshold, CooldownHours: resp.CooldownHours,
	})
}

func (o *Api) SendFundWithdrawalCode(c *gin.Context) {
	req, ok := bindFundWithdrawalSecurity(c)
	if !ok {
		return
	}
	resp, err := o.chatClient.SendFundWithdrawalCode(c, req)
	if err != nil {
		apiresp.GinError(c, err)
		return
	}
	apiresp.GinSuccess(c, resp)
}
