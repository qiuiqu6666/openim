package chat

import (
	"context"
	"errors"

	"github.com/openimsdk/chat/pkg/common/db/dbutil"
	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/fundswap"
	"github.com/openimsdk/chat/pkg/common/mctx"
	"github.com/openimsdk/chat/pkg/eerrs"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	"github.com/openimsdk/tools/errs"
)

type fundSwapService interface {
	GetConfig(context.Context) (*fundswap.Config, error)
	PutConfig(context.Context, string, []fundswap.PairConfig) (*fundswap.Config, error)
	Quote(context.Context, string, string, string, string) (*fundswap.Quote, error)
	Submit(context.Context, string, string, string, string, string, string) (*chatdb.FundOrder, error)
	FindByClient(context.Context, string, string) (*chatdb.FundOrder, error)
	Idempotent(context.Context, string, string, string, string, string, string) (*chatdb.FundOrder, error)
}

func swapError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, fundswap.ErrInvalid), errors.Is(err, fundswap.ErrOverflow):
		return errs.ErrArgs.WrapMsg("兑换数量或配置无效")
	case errors.Is(err, fundswap.ErrDisabled):
		return eerrs.ErrFundSwapDisabled.Wrap()
	case errors.Is(err, fundswap.ErrPriceUnavailable):
		return eerrs.ErrFundPriceUnavailable.WrapMsg("行情暂不可用，请稍后重试")
	case errors.Is(err, fundswap.ErrQuoteExpired):
		return eerrs.ErrFundQuoteExpired.Wrap()
	case errors.Is(err, fundswap.ErrQuoteUsed):
		return eerrs.ErrFundQuoteUsed.Wrap()
	case errors.Is(err, fundswap.ErrQuoteNotFound):
		return eerrs.ErrFundQuoteInvalid.Wrap()
	case errors.Is(err, fundswap.ErrConflict):
		return eerrs.ErrIdempotencyConflict.WrapMsg("业务单号已使用且参数不一致")
	case errors.Is(err, fundswap.ErrInsufficientBalance):
		return eerrs.ErrFundBalanceNotEnough.WrapMsg("可用余额不足")
	case errors.Is(err, fundswap.ErrNotFound):
		return eerrs.ErrFundOrderNotFound.Wrap()
	default:
		return err
	}
}

func (o *chatSvr) CreateFundSwapQuote(ctx context.Context, req *pb.CreateFundSwapQuoteReq) (*pb.CreateFundSwapQuoteResp, error) {
	user, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	quote, err := o.Swap.Quote(ctx, user, req.FromCurrency, req.ToCurrency, req.Amount)
	if err != nil {
		return nil, swapError(err)
	}
	return &pb.CreateFundSwapQuoteResp{
		QuoteID: quote.QuoteID, FromCurrency: quote.FromCurrency, ToCurrency: quote.ToCurrency,
		Amount: quote.Amount, EstimatedReceived: quote.EstimatedReceived, Rate: quote.Rate,
		MarketRate: quote.MarketRate, AdjustmentPercent: quote.AdjustmentPercent,
		InputValueUsd: quote.InputValueUsd, ExpiresAt: quote.ExpiresAt,
	}, nil
}

func (o *chatSvr) CreateFundSwap(ctx context.Context, req *pb.CreateFundSwapReq) (*pb.CreateFundSwapResp, error) {
	user, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	clientID, err := normalizeFundClientOrderID(req.ClientOrderID)
	if err != nil {
		return nil, err
	}
	req.ClientOrderID = clientID
	// A retry returns the committed result before checking mutable prices,
	// spending limits, quote expiry, or the current password state.
	existing, err := o.Swap.Idempotent(ctx, user, req.ClientOrderID, req.FromCurrency, req.ToCurrency, req.Amount, req.QuoteID)
	if err != nil {
		return nil, swapError(err)
	}
	if existing != nil {
		return swapResponse(existing), nil
	}
	if err = o.verifyFundPayPassword(ctx, user, req.PayPassword); err != nil {
		return nil, err
	}
	securityOrder, err := normalizeFundSwapSecurity(user, req)
	if err != nil {
		return nil, err
	}
	ctx, err = o.secureFundSpend(ctx, user, securityOrder, req.VerifyChallengeID, req.VerifyCode)
	if err != nil {
		return nil, err
	}
	order, err := o.Swap.Submit(ctx, user, req.ClientOrderID, req.FromCurrency, req.ToCurrency, req.Amount, req.QuoteID)
	if err != nil {
		return nil, swapError(err)
	}
	return swapResponse(order), nil
}

func swapResponse(order *chatdb.FundOrder) *pb.CreateFundSwapResp {
	return &pb.CreateFundSwapResp{Order: fundOrderPB(order), Received: formatFundAmount(order.TargetAmount, order.TargetCurrency)}
}

func (o *chatSvr) GetFundOrderByClient(ctx context.Context, req *pb.GetFundOrderByClientReq) (*pb.GetFundOrderResp, error) {
	user, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	clientOrderID, err := normalizeFundClientOrderID(req.ClientOrderID)
	if err != nil {
		return nil, err
	}
	order, err := o.Database.TakeFundOrderByClient(ctx, user, clientOrderID)
	if err != nil {
		if dbutil.IsDBNotFound(err) {
			return nil, eerrs.ErrFundOrderNotFound.Wrap()
		}
		return nil, err
	}
	if order == nil {
		return nil, eerrs.ErrFundOrderNotFound.Wrap()
	}
	return &pb.GetFundOrderResp{Order: fundOrderPB(order)}, nil
}

func swapConfigPB(config *fundswap.Config) *pb.GetFundSwapConfigResp {
	result := &pb.FundSwapConfig{QuoteTtlSeconds: int32(config.QuoteTtlSeconds), UpdatedAt: config.UpdatedAt, UpdatedBy: config.UpdatedBy}
	for _, pair := range config.Pairs {
		result.Pairs = append(result.Pairs, &pb.FundSwapPair{
			FromCurrency: pair.FromCurrency, ToCurrency: pair.ToCurrency, Enabled: pair.Enabled,
			AdjustmentPercent: pair.AdjustmentPercent, MarketRate: pair.MarketRate,
			EffectiveRate: pair.EffectiveRate, PriceStatus: pair.PriceStatus,
		})
	}
	return &pb.GetFundSwapConfigResp{Config: result}
}

func (o *chatSvr) GetFundSwapConfig(ctx context.Context, _ *pb.GetFundSwapConfigReq) (*pb.GetFundSwapConfigResp, error) {
	if _, err := mctx.CheckAdmin(ctx); err != nil {
		return nil, err
	}
	config, err := o.Swap.GetConfig(ctx)
	if err != nil {
		return nil, swapError(err)
	}
	return swapConfigPB(config), nil
}

func (o *chatSvr) PutFundSwapConfig(ctx context.Context, req *pb.PutFundSwapConfigReq) (*pb.GetFundSwapConfigResp, error) {
	admin, err := mctx.CheckAdmin(ctx)
	if err != nil {
		return nil, err
	}
	pairs := make([]fundswap.PairConfig, 0, len(req.Pairs))
	for _, p := range req.Pairs {
		if p == nil {
			return nil, errs.ErrArgs.WrapMsg("兑换方向配置无效")
		}
		pairs = append(pairs, fundswap.PairConfig{FromCurrency: p.FromCurrency, ToCurrency: p.ToCurrency, Enabled: p.Enabled, AdjustmentPercent: p.AdjustmentPercent})
	}
	config, err := o.Swap.PutConfig(ctx, admin, pairs)
	if err != nil {
		return nil, swapError(err)
	}
	return swapConfigPB(config), nil
}
