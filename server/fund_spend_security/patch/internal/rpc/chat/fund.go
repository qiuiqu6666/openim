package chat

import (
	"context"
	"encoding/json"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/openimsdk/chat/pkg/common/db/dbutil"
	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/mctx"
	"github.com/openimsdk/chat/pkg/eerrs"
	"github.com/openimsdk/chat/pkg/protocol/chat"
	"github.com/openimsdk/tools/errs"
)

func (o *chatSvr) ListFundBalances(ctx context.Context, _ *chat.ListFundBalancesReq) (*chat.ListFundBalancesResp, error) {
	userID, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := o.Database.ListFundBalances(ctx, userID)
	if err != nil {
		return nil, err
	}
	found := map[string]*chatdb.FundAccount{}
	for _, row := range rows {
		found[row.Currency] = row
	}
	resp := &chat.ListFundBalancesResp{}
	for _, currency := range []string{chatdb.FundCurrencyUSDT, chatdb.FundCurrencyTRX, chatdb.FundCurrencyBI99} {
		available, frozen := int64(0), int64(0)
		if row := found[currency]; row != nil {
			available, frozen = row.Available, row.Frozen
		}
		resp.Balances = append(resp.Balances, &chat.FundBalance{
			Currency:  currency,
			Available: formatFundAmount(available, currency),
			Frozen:    formatFundAmount(frozen, currency),
		})
	}
	return resp, nil
}

func (o *chatSvr) CreateFundPacket(ctx context.Context, req *chat.CreateFundPacketReq) (*chat.CreateFundPacketResp, error) {
	userID, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	securityOrder, err := normalizeFundPacketSecurity(userID, req)
	if err != nil {
		return nil, err
	}
	req.ClientOrderID = securityOrder.ClientOrderID
	if existing, err := o.acceptedPacket(ctx, securityOrder); err != nil || existing != nil {
		if err != nil {
			return nil, err
		}
		if existing.Scene == chatdb.FundSceneGroup && existing.Biz != chatdb.FundBizPacketExclusive {
			if err = o.publishFundGrab(ctx, existing); err != nil {
				return nil, err
			}
		}
		return &chat.CreateFundPacketResp{Order: fundOrderPB(existing)}, nil
	}
	if err = o.verifyFundPayPassword(ctx, userID, req.PayPassword); err != nil {
		return nil, err
	}
	ctx, err = o.secureFundSpend(ctx, userID, securityOrder, req.VerifyChallengeID, req.VerifyCode)
	if err != nil {
		return nil, err
	}
	remark, err := normalizeFundRemark(req.Remark, true)
	if err != nil {
		return nil, err
	}
	switch req.Biz {
	case chatdb.FundBizPacketExclusive:
		order, err := o.prepareDirect(ctx, userID, req.ClientOrderID, req.Scene, req.Currency, req.Amount, req.RecvID, req.GroupID, req.Biz, remark)
		if err != nil {
			return nil, err
		}
		saved, err := o.Database.CreateDirectFundOrder(ctx, order)
		if err != nil {
			return nil, err
		}
		return &chat.CreateFundPacketResp{Order: fundOrderPB(saved)}, nil
	case chatdb.FundBizPacketNormal:
		if req.Scene == chatdb.FundSceneSingle {
			order, err := o.prepareDirect(ctx, userID, req.ClientOrderID, req.Scene, req.Currency, req.Amount, req.RecvID, req.GroupID, req.Biz, remark)
			if err != nil {
				return nil, err
			}
			saved, err := o.Database.CreateDirectFundOrder(ctx, order)
			if err != nil {
				return nil, err
			}
			return &chat.CreateFundPacketResp{Order: fundOrderPB(saved)}, nil
		}
		if req.Scene != chatdb.FundSceneGroup {
			return nil, errs.ErrArgs.WrapMsg("scene invalid")
		}
		share, err := parseFundAmount(req.ShareAmount, req.Currency)
		if err != nil {
			return nil, err
		}
		if err = alignPacketGrabAmount(share, req.Currency); err != nil {
			return nil, err
		}
		if req.ShareCount < 1 {
			return nil, errs.ErrArgs.WrapMsg("share count invalid")
		}
		total := share * int64(req.ShareCount)
		if err = o.prepareGroupSender(ctx, userID, req.GroupID, chatdb.FundBizPacketNormal, req.Currency, total); err != nil {
			return nil, err
		}
		shares := make([]int64, req.ShareCount)
		for i := range shares {
			shares[i] = share
		}
		saved, err := o.Database.CreatePacketFundOrder(ctx, &chatdb.FundOrder{
			ClientOrderID: req.ClientOrderID, Biz: req.Biz, Scene: req.Scene, Currency: req.Currency,
			SenderID: userID, GroupID: req.GroupID, Amount: total, ShareAmount: share, ShareCount: req.ShareCount,
			Remark: remark,
		}, shares)
		if err != nil {
			return nil, err
		}
		if err = o.publishFundGrab(ctx, saved); err != nil {
			return nil, err
		}
		return &chat.CreateFundPacketResp{Order: fundOrderPB(saved)}, nil
	case chatdb.FundBizPacketLucky:
		if req.Scene != chatdb.FundSceneGroup {
			return nil, errs.ErrArgs.WrapMsg("lucky packet is group only")
		}
		total, err := parseFundAmount(req.Amount, req.Currency)
		if err != nil {
			return nil, err
		}
		if err = alignPacketGrabAmount(total, req.Currency); err != nil {
			return nil, err
		}
		if err = o.prepareGroupSender(ctx, userID, req.GroupID, req.Biz, req.Currency, total); err != nil {
			return nil, err
		}
		unit := packetGrabUnit(req.Currency)
		shares, err := splitLuckyShares(total/unit, int(req.ShareCount))
		if err != nil {
			return nil, err
		}
		for i := range shares {
			shares[i] *= unit
		}
		saved, err := o.Database.CreatePacketFundOrder(ctx, &chatdb.FundOrder{
			ClientOrderID: req.ClientOrderID, Biz: req.Biz, Scene: req.Scene, Currency: req.Currency,
			SenderID: userID, GroupID: req.GroupID, Amount: total, ShareCount: req.ShareCount,
			Remark: remark,
		}, shares)
		if err != nil {
			return nil, err
		}
		if err = o.publishFundGrab(ctx, saved); err != nil {
			return nil, err
		}
		return &chat.CreateFundPacketResp{Order: fundOrderPB(saved)}, nil
	default:
		return nil, errs.ErrArgs.WrapMsg("biz invalid")
	}
}

func (o *chatSvr) ClaimFundPacket(ctx context.Context, req *chat.ClaimFundPacketReq) (*chat.ClaimFundPacketResp, error) {
	userID, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	order, _, err := o.Database.TakeFundOrder(ctx, req.OrderID)
	if err != nil {
		if dbutil.IsDBNotFound(err) {
			return nil, eerrs.ErrFundOrderNotFound.Wrap()
		}
		return nil, err
	}
	if order.Biz != chatdb.FundBizPacketNormal && order.Biz != chatdb.FundBizPacketLucky {
		return nil, eerrs.ErrFundPacketClosed.Wrap()
	}
	if order.Status != chatdb.FundStatusOpen || !order.ExpireAt.After(time.Now()) {
		return nil, eerrs.ErrFundPacketClosed.Wrap()
	}
	index, amount, err := o.grabFundShare(ctx, order, userID)
	if err != nil {
		return nil, err
	}
	share := &chatdb.FundShare{OrderID: order.OrderID, Index: index, Amount: amount, ClaimerID: userID, ClaimedAt: time.Now()}
	return &chat.ClaimFundPacketResp{Order: fundOrderPB(order), Share: fundSharePB(share, order.Currency)}, nil
}

func (o *chatSvr) GetFundOrder(ctx context.Context, req *chat.GetFundOrderReq) (*chat.GetFundOrderResp, error) {
	userID, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	order, shares, err := o.Database.TakeFundOrder(ctx, req.OrderID)
	if err != nil {
		if dbutil.IsDBNotFound(err) {
			return nil, eerrs.ErrFundOrderNotFound.Wrap()
		}
		return nil, err
	}
	if order.SenderID != userID && order.RecvID != userID {
		if order.GroupID == "" {
			return nil, eerrs.ErrFundOrderNotFound.Wrap()
		}
		if err = o.requireFundGroupMember(ctx, order.GroupID, userID); err != nil {
			return nil, err
		}
	}
	resp := &chat.GetFundOrderResp{Order: fundOrderPB(order)}
	for _, share := range shares {
		resp.Shares = append(resp.Shares, fundSharePB(share, order.Currency))
	}
	return resp, nil
}

func (o *chatSvr) MarkFundMessageSent(ctx context.Context, req *chat.MarkFundMessageSentReq) (*chat.MarkFundMessageSentResp, error) {
	if _, _, err := mctx.Check(ctx); err != nil {
		return nil, err
	}
	if err := o.Database.MarkFundMessageSent(ctx, req.OrderID); err != nil {
		return nil, err
	}
	return &chat.MarkFundMessageSentResp{}, nil
}

const fundPacketRemarkDefault = "恭喜发财，大吉大利"

func normalizeFundRemark(raw string, packet bool) (string, error) {
	remark := strings.TrimSpace(raw)
	if utf8.RuneCountInString(remark) > 12 {
		return "", errs.ErrArgs.WrapMsg("remark too long")
	}
	if packet && remark == "" {
		return fundPacketRemarkDefault, nil
	}
	return remark, nil
}

func (o *chatSvr) prepareDirect(ctx context.Context, userID, clientOrderID, scene, currency, amount, recvID, groupID, biz, remark string) (*chatdb.FundOrder, error) {
	if strings.TrimSpace(clientOrderID) == "" || recvID == "" || recvID == userID {
		return nil, errs.ErrArgs.WrapMsg("order invalid")
	}
	minor, err := parseFundAmount(amount, currency)
	if err != nil {
		return nil, err
	}
	switch scene {
	case chatdb.FundSceneSingle:
		if biz == "" {
			biz = chatdb.FundBizTransfer
		}
		groupID = ""
	case chatdb.FundSceneGroup:
		if biz == "" {
			biz = chatdb.FundBizGroupTransfer
		}
		if groupID == "" {
			return nil, errs.ErrArgs.WrapMsg("groupID empty")
		}
		if err = o.requireFundGroupMember(ctx, groupID, userID); err != nil {
			return nil, err
		}
		if err = o.requireFundGroupMember(ctx, groupID, recvID); err != nil {
			return nil, err
		}
	default:
		return nil, errs.ErrArgs.WrapMsg("scene invalid")
	}
	if err = o.checkFundSpend(ctx, userID, biz, currency, minor); err != nil {
		return nil, err
	}
	return &chatdb.FundOrder{
		ClientOrderID: clientOrderID, Biz: biz, Scene: scene, Currency: currency,
		SenderID: userID, RecvID: recvID, GroupID: groupID, Amount: minor, Remark: remark,
	}, nil
}

func (o *chatSvr) prepareGroupSender(ctx context.Context, userID, groupID, biz, currency string, amount int64) error {
	if groupID == "" {
		return errs.ErrArgs.WrapMsg("groupID empty")
	}
	if err := o.requireFundGroupMember(ctx, groupID, userID); err != nil {
		return err
	}
	return o.checkFundSpend(ctx, userID, biz, currency, amount)
}

func (o *chatSvr) requireFundGroupMember(ctx context.Context, groupID, userID string) error {
	imCtx, err := o.withIMAdmin(ctx)
	if err != nil {
		return err
	}
	roles, err := o.IM.GroupMemberRoles(imCtx, groupID, []string{userID})
	if err != nil {
		return err
	}
	if _, ok := roles[userID]; !ok {
		return eerrs.ErrFundNotInGroup.Wrap()
	}
	return nil
}

func fundOrderPB(order *chatdb.FundOrder) *chat.FundOrder {
	if order == nil {
		return nil
	}
	var expire int64
	if !order.ExpireAt.IsZero() {
		expire = order.ExpireAt.UnixMilli()
	}
	return &chat.FundOrder{
		OrderID: order.OrderID, Biz: order.Biz, Scene: order.Scene, Currency: order.Currency,
		Amount: formatFundAmount(order.Amount, order.Currency), Status: order.Status,
		RecvID: order.RecvID, GroupID: order.GroupID, CreatedAt: order.CreatedAt.UnixMilli(), ExpireAt: expire,
		ShareAmount: formatFundAmount(order.ShareAmount, order.Currency), ShareCount: order.ShareCount,
		TargetCurrency: order.TargetCurrency, TargetAmount: formatFundAmount(order.TargetAmount, order.TargetCurrency),
		Fee: formatFundAmount(order.Fee, order.Currency), ToAddress: order.ToAddress,
		Remark:        order.Remark,
		ClientOrderID: order.ClientOrderID, SenderID: order.SenderID,
		QuoteID: order.QuoteID, Rate: order.Rate, MarketRate: order.MarketRate, AdjustmentPercent: order.AdjustmentPercent,
		ChainTxID: order.ChainTxID, FromAddress: order.FromAddress,
		Network: order.Network, RecipientType: order.RecipientType, Recipient: order.Recipient, RecipientAreaCode: order.RecipientAreaCode,
		ReviewedBy: order.ReviewedBy, ReviewReason: order.ReviewReason, ReviewedAt: fundTimestamp(order.ReviewedAt), CompletedAt: fundTimestamp(order.CompletedAt),
		CompletedBy: order.CompletedBy, CompletionReason: order.CompletionReason,
	}
}

func fundTimestamp(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return t.UnixMilli()
}

func fundSharePB(share *chatdb.FundShare, currency string) *chat.FundShare {
	if share == nil {
		return nil
	}
	var claimed int64
	if !share.ClaimedAt.IsZero() && share.ClaimerID != "" && !strings.HasPrefix(share.ClaimerID, "refund:") {
		claimed = share.ClaimedAt.UnixMilli()
	}
	claimer := share.ClaimerID
	if strings.HasPrefix(claimer, "refund:") {
		claimer = ""
	}
	return &chat.FundShare{Index: share.Index, Amount: formatFundAmount(share.Amount, currency), ClaimerID: claimer, ClaimedAt: claimed}
}

func fundMessageData(order *chatdb.FundOrder) string {
	body, _ := json.Marshal(map[string]any{
		"orderID": order.OrderID, "biz": order.Biz, "currency": order.Currency,
		"amount": formatFundAmount(order.Amount, order.Currency), "status": order.Status,
		"remark": order.Remark,
	})
	return string(body)
}
