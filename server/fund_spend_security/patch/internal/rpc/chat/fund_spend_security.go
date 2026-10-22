package chat

import (
	"context"
	"math"
	"strings"

	"github.com/openimsdk/chat/pkg/common/db/dbutil"
	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"github.com/openimsdk/chat/pkg/eerrs"
	"github.com/openimsdk/chat/pkg/grouplive"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	livepb "github.com/openimsdk/chat/pkg/protocol/live"
	"github.com/openimsdk/tools/errs"
)

func normalizeFundPacketSecurity(user string, req *pb.CreateFundPacketReq) (*chatdb.FundOrder, error) {
	id, err := normalizeFundClientOrderID(req.ClientOrderID)
	if err != nil {
		return nil, err
	}
	remark, err := normalizeFundRemark(req.Remark, true)
	if err != nil {
		return nil, err
	}
	o := &chatdb.FundOrder{SenderID: user, ClientOrderID: id, Biz: req.Biz, Scene: req.Scene, Currency: req.Currency, RecvID: req.RecvID, GroupID: req.GroupID, Remark: remark}
	if o.Scene != chatdb.FundSceneSingle && o.Scene != chatdb.FundSceneGroup {
		return nil, errs.ErrArgs.WrapMsg("红包场景无效")
	}
	if o.Scene == chatdb.FundSceneSingle {
		o.GroupID = ""
	}
	if o.Biz != chatdb.FundBizPacketExclusive && o.Biz != chatdb.FundBizPacketNormal && o.Biz != chatdb.FundBizPacketLucky {
		return nil, errs.ErrArgs.WrapMsg("红包类型无效")
	}
	if o.Scene == chatdb.FundSceneGroup && o.Biz != chatdb.FundBizPacketExclusive {
		if req.ShareCount < 1 || req.ShareCount > 10000 {
			return nil, errs.ErrArgs.WrapMsg("红包份数无效")
		}
		o.ShareCount = req.ShareCount
		o.RecvID = ""
	}
	if o.Biz == chatdb.FundBizPacketNormal && o.Scene == chatdb.FundSceneGroup {
		o.ShareAmount, err = parseFundAmount(req.ShareAmount, o.Currency)
		if err != nil {
			return nil, err
		}
		if o.ShareAmount > math.MaxInt64/int64(o.ShareCount) {
			return nil, errs.ErrArgs.WrapMsg("红包金额超出范围")
		}
		o.Amount = o.ShareAmount * int64(o.ShareCount)
	} else {
		o.Amount, err = parseFundAmount(req.Amount, o.Currency)
	}
	if err != nil {
		return nil, err
	}
	return o, nil
}

func normalizeFundSwapSecurity(user string, req *pb.CreateFundSwapReq) (*chatdb.FundOrder, error) {
	id, err := normalizeFundClientOrderID(req.ClientOrderID)
	if err != nil {
		return nil, err
	}
	amount, err := parseFundAmount(req.Amount, req.FromCurrency)
	if err != nil {
		return nil, err
	}
	if req.FromCurrency == req.ToCurrency || (req.ToCurrency != "USDT" && req.ToCurrency != "TRX" && req.ToCurrency != "BI99") {
		return nil, errs.ErrArgs.WrapMsg("兑换币种无效")
	}
	return &chatdb.FundOrder{SenderID: user, ClientOrderID: id, Biz: chatdb.FundBizSwap, Currency: req.FromCurrency, TargetCurrency: req.ToCurrency, Amount: amount, QuoteID: req.QuoteID}, nil
}

func (o *chatSvr) normalizeFundTipSecurity(ctx context.Context, user string, req *livepb.TipLiveReq) (*chatdb.FundOrder, error) {
	id, err := normalizeFundClientOrderID(req.ClientOrderId)
	if err != nil {
		return nil, err
	}
	if req.Amount < 1 || req.Amount > grouplive.MaxTipAmount || !grouplive.AllowedCurrency(req.Currency) || strings.TrimSpace(req.SessionID) == "" {
		return nil, errs.ErrArgs.WrapMsg("打赏参数无效")
	}
	memo, err := grouplive.NormalizeMemo(req.Memo)
	if err != nil {
		return nil, err
	}
	session, err := o.Database.TakeLiveSession(ctx, req.SessionID)
	if err != nil {
		return nil, err
	}
	// Session is carried in the ephemeral security descriptor, never as a chain address.
	return &chatdb.FundOrder{SenderID: user, ClientOrderID: id, Biz: chatdb.FundBizLiveTip, Scene: chatdb.FundSceneGroup, Currency: req.Currency, Amount: req.Amount, RecvID: session.AnchorUserID, GroupID: session.GroupID, Remark: memo, ToAddress: req.SessionID}, nil
}

func (o *chatSvr) acceptedPacket(ctx context.Context, request *chatdb.FundOrder) (*chatdb.FundOrder, error) {
	saved, err := o.Database.TakeFundOrderByClient(ctx, request.SenderID, request.ClientOrderID)
	if dbutil.IsDBNotFound(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if saved == nil {
		return nil, nil
	}
	if saved.Biz != request.Biz || saved.Scene != request.Scene || saved.Currency != request.Currency || saved.Amount != request.Amount || saved.RecvID != request.RecvID || saved.GroupID != request.GroupID || saved.Remark != request.Remark || saved.ShareCount != request.ShareCount || saved.ShareAmount != request.ShareAmount {
		return nil, eerrs.ErrIdempotencyConflict.Wrap()
	}
	return saved, nil
}

func (o *chatSvr) secureFundSpend(ctx context.Context, user string, order *chatdb.FundOrder, challenge, code string) (context.Context, error) {
	subject, err := o.prepareFundWithdrawalSecurity(ctx, user, order, challenge, code)
	if err != nil {
		return nil, err
	}
	return fundsecurity.WithSpendGuard(ctx, func(tx context.Context) error {
		if err := o.checkFundSpend(tx, user, order.Biz, order.Currency, order.Amount); err != nil {
			return err
		}
		return o.guardFundWithdrawalSecurity(tx, subject, order, challenge, code)
	}), nil
}

func (o *chatSvr) acceptedAdditionalSecurity(ctx context.Context, user string, req *pb.FundWithdrawalSecurityReq, order *chatdb.FundOrder) (bool, error) {
	if req.Packet != nil {
		row, err := o.acceptedPacket(ctx, order)
		return row != nil, err
	}
	if req.Swap != nil {
		r := req.Swap
		row, err := o.Swap.Idempotent(ctx, user, order.ClientOrderID, r.FromCurrency, r.ToCurrency, r.Amount, r.QuoteID)
		return row != nil, swapError(err)
	}
	if req.Tip != nil {
		row, err := o.Database.TakeLiveTip(ctx, user, order.ClientOrderID)
		if dbutil.IsDBNotFound(err) {
			return false, nil
		}
		if err != nil {
			return false, err
		}
		if row == nil {
			return false, nil
		}
		if row.ParamHash != grouplive.TipHash(req.Tip.SessionID, req.Tip.Currency, order.Remark, req.Tip.Amount) {
			return false, eerrs.ErrIdempotencyConflict.Wrap()
		}
		return true, nil
	}
	return false, nil
}
