package database

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"math"
	"time"

	"github.com/openimsdk/chat/pkg/common/db/dbutil"
	chatmodel "github.com/openimsdk/chat/pkg/common/db/model/chat"
	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/eerrs"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/mongo"
)

func fundErr(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, chatmodel.ErrFundShort) || errors.Is(errs.Unwrap(err), chatmodel.ErrFundShort) {
		return eerrs.ErrFundBalanceNotEnough.Wrap()
	}
	if errors.Is(err, chatmodel.ErrFundOverflow) || errors.Is(errs.Unwrap(err), chatmodel.ErrFundOverflow) {
		return errs.ErrArgs.WrapMsg("账户余额超过允许范围")
	}
	return err
}

func fundDup(err error) bool {
	return mongo.IsDuplicateKeyError(err) || mongo.IsDuplicateKeyError(errs.Unwrap(err))
}

func (o *ChatDatabase) ListFundBalances(ctx context.Context, userID string) ([]*chatdb.FundAccount, error) {
	return o.fund.ListAccounts(ctx, userID)
}

func (o *ChatDatabase) TakeFundOrderByClient(ctx context.Context, userID, clientOrderID string) (*chatdb.FundOrder, error) {
	return o.fund.TakeOrderByClient(ctx, userID, clientOrderID)
}

func (o *ChatDatabase) TakeFundOrder(ctx context.Context, orderID string) (*chatdb.FundOrder, []*chatdb.FundShare, error) {
	order, err := o.fund.TakeOrder(ctx, orderID)
	if err != nil {
		return nil, nil, err
	}
	shares, err := o.fund.ListShares(ctx, orderID)
	if err != nil {
		return nil, nil, err
	}
	return order, shares, nil
}

func (o *ChatDatabase) CreateDirectFundOrder(ctx context.Context, order *chatdb.FundOrder) (*chatdb.FundOrder, error) {
	return o.CreateDirectFundOrderChecked(ctx, order, nil)
}

func (o *ChatDatabase) CreateInternalFundOrder(ctx context.Context, order *chatdb.FundOrder, beforeSpend func(context.Context) error) (*chatdb.FundOrder, error) {
	if order == nil || order.Scene != chatdb.FundSceneInternal || order.Biz != chatdb.FundBizTransfer || order.Fee != 0 || order.ToAddress != "" || order.Network != "" {
		return nil, errs.ErrArgs.WrapMsg("站内转账参数错误")
	}
	return o.CreateDirectFundOrderChecked(ctx, order, beforeSpend)
}

func (o *ChatDatabase) CreateDirectFundOrderChecked(ctx context.Context, order *chatdb.FundOrder, beforeSpend func(context.Context) error) (*chatdb.FundOrder, error) {
	if order == nil || order.Amount <= 0 || order.SenderID == "" || order.RecvID == "" || order.SenderID == order.RecvID || order.ClientOrderID == "" || order.Fee != 0 {
		return nil, errs.ErrArgs.WrapMsg("转账参数错误")
	}
	var saved *chatdb.FundOrder
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		saved = nil
		existing, err := o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
		if err == nil {
			if !sameDirectFundRequest(existing, order) {
				return eerrs.ErrIdempotencyConflict.WrapMsg("业务单号已使用且参数不一致")
			}
			saved = existing
			return nil
		}
		if !dbutil.IsDBNotFound(err) {
			return err
		}
		if err = o.fund.DebitAvailable(ctx, order.SenderID, order.Currency, order.Amount); err != nil {
			return err
		}
		if err = fundsecurity.RunSpendGuard(ctx); err != nil {
			return err
		}
		if beforeSpend != nil {
			if err = beforeSpend(ctx); err != nil {
				return err
			}
		}
		if err = o.fund.CreditAvailable(ctx, order.RecvID, order.Currency, order.Amount); err != nil {
			return err
		}
		now := time.Now()
		order.OrderID, err = newFundOrderID()
		if err != nil {
			return err
		}
		order.Status = chatdb.FundStatusDone
		order.CreatedAt = now
		if order.Scene == chatdb.FundSceneInternal {
			order.CompletedAt = now
			order.MessageSent = true
		}
		if err = o.fund.InsertOrder(ctx, order); err != nil {
			return err
		}
		if err = o.writeFundJournal(ctx, order.SenderID, order.Currency, order.Biz, order.OrderID+":out", -order.Amount, 0, now); err != nil {
			return err
		}
		return o.writeFundJournal(ctx, order.RecvID, order.Currency, order.Biz, order.OrderID+":in", order.Amount, 0, now)
	})
	if err != nil {
		if fundDup(err) {
			existing, takeErr := o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
			if takeErr != nil {
				return nil, fundErr(err)
			}
			if !sameDirectFundRequest(existing, order) {
				return nil, eerrs.ErrIdempotencyConflict.WrapMsg("业务单号已使用且参数不一致")
			}
			return existing, nil
		}
		return nil, fundErr(err)
	}
	if saved == nil {
		saved = order
	}
	return saved, nil
}

func (o *ChatDatabase) CreatePacketFundOrder(ctx context.Context, order *chatdb.FundOrder, shares []int64) (*chatdb.FundOrder, error) {
	var saved *chatdb.FundOrder
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		existing, err := o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
		if err == nil {
			if !sameDirectFundRequest(existing, order) {
				return eerrs.ErrIdempotencyConflict.Wrap()
			}
			saved = existing
			return nil
		}
		if !dbutil.IsDBNotFound(err) {
			return err
		}
		if err = fundsecurity.RunSpendGuard(ctx); err != nil {
			return err
		}
		if err = o.fund.Freeze(ctx, order.SenderID, order.Currency, order.Amount); err != nil {
			return err
		}
		now := time.Now()
		order.OrderID, err = newFundOrderID()
		if err != nil {
			return err
		}
		order.Status = chatdb.FundStatusOpen
		order.CreatedAt = now
		order.ExpireAt = now.Add(24 * time.Hour)
		rows := make([]*chatdb.FundShare, len(shares))
		for i, amount := range shares {
			rows[i] = &chatdb.FundShare{OrderID: order.OrderID, Index: int32(i), Amount: amount}
		}
		if err = o.fund.InsertShares(ctx, rows); err != nil {
			return err
		}
		if err = o.fund.InsertOrder(ctx, order); err != nil {
			return err
		}
		return o.writeFundJournal(ctx, order.SenderID, order.Currency, order.Biz, order.OrderID+":freeze", -order.Amount, order.Amount, now)
	})
	if err != nil {
		if fundDup(err) {
			existing, takeErr := o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
			if takeErr != nil {
				return nil, fundErr(err)
			}
			if !sameDirectFundRequest(existing, order) {
				return nil, eerrs.ErrIdempotencyConflict.Wrap()
			}
			return existing, nil
		}
		return nil, fundErr(err)
	}
	if saved == nil {
		saved = order
	}
	return saved, nil
}

func (o *ChatDatabase) ClaimFundShare(ctx context.Context, orderID, userID string, now time.Time) (*chatdb.FundOrder, *chatdb.FundShare, error) {
	var order *chatdb.FundOrder
	var share *chatdb.FundShare
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		current, err := o.fund.TakeOrder(ctx, orderID)
		if err != nil {
			return err
		}
		order = current
		if current.Status != chatdb.FundStatusOpen || !current.ExpireAt.After(now) {
			return eerrs.ErrFundPacketClosed.Wrap()
		}
		if _, err = o.fund.TakeShareByClaimer(ctx, orderID, userID); err == nil {
			return eerrs.ErrFundAlreadyClaimed.Wrap()
		} else if !dbutil.IsDBNotFound(err) {
			return err
		}
		share, err = o.fund.ClaimEmptyShare(ctx, orderID, userID, now)
		if err != nil {
			if dbutil.IsDBNotFound(err) {
				return eerrs.ErrFundPacketClosed.Wrap()
			}
			if fundDup(err) {
				return eerrs.ErrFundAlreadyClaimed.Wrap()
			}
			return err
		}
		if err = o.fund.DebitFrozen(ctx, current.SenderID, current.Currency, share.Amount); err != nil {
			return err
		}
		if err = o.fund.CreditAvailable(ctx, userID, current.Currency, share.Amount); err != nil {
			return err
		}
		bizID := orderID + ":share:" + itoa(share.Index)
		if err = o.writeFundJournal(ctx, current.SenderID, current.Currency, current.Biz, bizID, 0, -share.Amount, now); err != nil {
			return err
		}
		if err = o.writeFundJournal(ctx, userID, current.Currency, current.Biz, bizID+":in", share.Amount, 0, now); err != nil {
			return err
		}
		left, err := o.fund.CountOpenShares(ctx, orderID)
		if err != nil {
			return err
		}
		if left == 0 {
			if err = o.fund.UpdateOrder(ctx, orderID, map[string]any{"status": chatdb.FundStatusDone}); err != nil {
				return err
			}
			current.Status = chatdb.FundStatusDone
		}
		return nil
	})
	if err != nil {
		return nil, nil, fundErr(err)
	}
	return order, share, nil
}

type FundSettleItem struct {
	OrderID string
	UserID  string
	Index   int32
	Amount  int64
}

func (o *ChatDatabase) ListExpiredFundOrders(ctx context.Context, now time.Time, limit int64) ([]*chatdb.FundOrder, error) {
	return o.fund.ListExpiredOpen(ctx, now, limit)
}

func (o *ChatDatabase) ListOpenFundPackets(ctx context.Context, limit int64) ([]*chatdb.FundOrder, error) {
	return o.fund.ListOpenPackets(ctx, limit)
}

func (o *ChatDatabase) RefundFundRemainder(ctx context.Context, orderID string, amount int64, now time.Time) (bool, error) {
	refunded := false
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		refunded = false
		current, err := o.fund.TakeOrder(ctx, orderID)
		if err != nil {
			return err
		}
		if current.Status != chatdb.FundStatusOpen {
			return nil
		}
		if amount > 0 {
			if err = o.fund.Unfreeze(ctx, current.SenderID, current.Currency, amount); err != nil {
				return err
			}
			if err = o.writeFundJournal(ctx, current.SenderID, current.Currency, current.Biz, current.OrderID+":refund", amount, -amount, now); err != nil {
				return err
			}
		}
		ok, err := o.fund.RefundOrderIfOpen(ctx, current.OrderID)
		if err != nil {
			return err
		}
		refunded = ok
		return nil
	})
	if err != nil && !fundDup(err) {
		return false, fundErr(err)
	}
	if err != nil {
		return false, nil
	}
	return refunded, nil
}

func (o *ChatDatabase) SettleFundClaims(ctx context.Context, items []FundSettleItem) error {
	grouped := make(map[string][]FundSettleItem)
	for _, item := range items {
		grouped[item.OrderID] = append(grouped[item.OrderID], item)
	}
	for orderID, batch := range grouped {
		err := o.tx.Transaction(ctx, func(ctx context.Context) error {
			current, err := o.fund.TakeOrder(ctx, orderID)
			if err != nil {
				return err
			}
			now := time.Now()
			var pending []FundSettleItem
			var sum int64
			for _, item := range batch {
				share, err := o.fund.TakeShareByIndex(ctx, orderID, item.Index)
				if err != nil {
					return err
				}
				if share.ClaimerID != "" {
					continue
				}
				inID := orderID + ":share:" + itoa(item.Index) + ":in"
				exists, err := o.fund.HasJournal(ctx, current.Biz, inID, item.UserID, current.Currency)
				if err != nil {
					return err
				}
				if exists {
					continue
				}
				pending = append(pending, item)
				sum += item.Amount
			}
			if sum > 0 {
				if err = o.fund.DebitFrozen(ctx, current.SenderID, current.Currency, sum); err != nil {
					return err
				}
			}
			for _, item := range pending {
				bizID := orderID + ":share:" + itoa(item.Index)
				if err = o.fund.CreditAvailable(ctx, item.UserID, current.Currency, item.Amount); err != nil {
					return err
				}
				if err = o.writeFundJournal(ctx, current.SenderID, current.Currency, current.Biz, bizID, 0, -item.Amount, now); err != nil {
					return err
				}
				if err = o.writeFundJournal(ctx, item.UserID, current.Currency, current.Biz, bizID+":in", item.Amount, 0, now); err != nil {
					return err
				}
				if err = o.fund.SetShareClaimer(ctx, orderID, item.Index, item.UserID, now); err != nil {
					return err
				}
			}
			claimed, err := o.fund.CountClaimedShares(ctx, orderID)
			if err != nil {
				return err
			}
			if claimed >= int64(current.ShareCount) {
				return o.fund.FinishOrderIfOpen(ctx, orderID)
			}
			return nil
		})
		if err != nil {
			return fundErr(err)
		}
	}
	return nil
}

func (o *ChatDatabase) SumFundOutgoing(ctx context.Context, userID, currency string, start, end time.Time) (int64, error) {
	return o.fund.SumOutgoing(ctx, userID, currency, start, end)
}

func (o *ChatDatabase) GetFundConfig(ctx context.Context) (*chatdb.FundConfig, error) {
	cfg, err := o.fund.GetConfig(ctx)
	if err != nil {
		if dbutil.IsDBNotFound(err) {
			return &chatdb.FundConfig{ID: "default"}, nil
		}
		return nil, err
	}
	return cfg, nil
}

func (o *ChatDatabase) PutFundConfig(ctx context.Context, cfg *chatdb.FundConfig) error {
	old, err := o.GetFundConfig(ctx)
	if err != nil {
		return err
	}
	if cfg.TronPrivateKey == "" {
		cfg.TronPrivateKey = old.TronPrivateKey
	}
	return o.fund.PutConfig(ctx, cfg)
}

func (o *ChatDatabase) TakeFundPrice(ctx context.Context, pair string) (*chatdb.FundPrice, error) {
	return o.fund.TakePrice(ctx, pair)
}

func (o *ChatDatabase) UpsertFundPrice(ctx context.Context, pair, price string, fetched time.Time) error {
	return o.fund.UpsertPrice(ctx, pair, price, fetched)
}

func (o *ChatDatabase) CreateSwapFundOrder(ctx context.Context, order *chatdb.FundOrder) (*chatdb.FundOrder, error) {
	var saved *chatdb.FundOrder
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		existing, err := o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
		if err == nil {
			saved = existing
			return nil
		}
		if !dbutil.IsDBNotFound(err) {
			return err
		}
		if err = o.fund.DebitAvailable(ctx, order.SenderID, order.Currency, order.Amount); err != nil {
			return err
		}
		if err = o.fund.CreditAvailable(ctx, order.SenderID, order.TargetCurrency, order.TargetAmount); err != nil {
			return err
		}
		now := time.Now()
		order.OrderID, err = newFundOrderID()
		if err != nil {
			return err
		}
		order.Status = chatdb.FundStatusDone
		order.CreatedAt = now
		order.MessageSent = true
		if err = o.fund.InsertOrder(ctx, order); err != nil {
			return err
		}
		if err = o.writeFundJournal(ctx, order.SenderID, order.Currency, order.Biz, order.OrderID+":out", -order.Amount, 0, now); err != nil {
			return err
		}
		return o.writeFundJournal(ctx, order.SenderID, order.TargetCurrency, order.Biz, order.OrderID+":in", order.TargetAmount, 0, now)
	})
	if err != nil {
		if fundDup(err) {
			return o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
		}
		return nil, fundErr(err)
	}
	if saved == nil {
		saved = order
	}
	return saved, nil
}

func (o *ChatDatabase) CreateWithdrawFundOrder(ctx context.Context, order *chatdb.FundOrder) (*chatdb.FundOrder, error) {
	return o.CreateWithdrawFundOrderChecked(ctx, order, nil)
}

func (o *ChatDatabase) CreateWithdrawFundOrderChecked(ctx context.Context, order *chatdb.FundOrder, beforeSpend func(context.Context) error) (*chatdb.FundOrder, error) {
	if order == nil || order.Amount <= 0 || order.SenderID == "" || order.ClientOrderID == "" || order.Biz != chatdb.FundBizWithdraw || order.Scene == chatdb.FundSceneInternal {
		return nil, errs.ErrArgs.WrapMsg("提现参数错误")
	}
	var saved *chatdb.FundOrder
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		saved = nil
		existing, err := o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
		if err == nil {
			if !sameWithdrawFundRequest(existing, order) {
				return eerrs.ErrIdempotencyConflict.WrapMsg("业务单号已使用且参数不一致")
			}
			saved = existing
			return nil
		}
		if !dbutil.IsDBNotFound(err) {
			return err
		}
		if order.Amount <= 0 || order.Fee < 0 || order.Amount > math.MaxInt64-order.Fee {
			return errs.ErrArgs.WrapMsg("提现金额或手续费超出允许范围")
		}
		total := order.Amount + order.Fee
		if err = o.fund.Freeze(ctx, order.SenderID, order.Currency, total); err != nil {
			return err
		}
		if beforeSpend != nil {
			if err = beforeSpend(ctx); err != nil {
				return err
			}
		}
		now := time.Now()
		order.OrderID, err = newFundOrderID()
		if err != nil {
			return err
		}
		order.Status = chatdb.FundStatusWithdrawPending
		order.CreatedAt = now
		order.MessageSent = true
		if err = o.fund.InsertOrder(ctx, order); err != nil {
			return err
		}
		return o.writeFundJournal(ctx, order.SenderID, order.Currency, order.Biz, order.OrderID+":freeze", -total, total, now)
	})
	if err != nil {
		if fundDup(err) {
			existing, takeErr := o.fund.TakeOrderByClient(ctx, order.SenderID, order.ClientOrderID)
			if takeErr != nil {
				return nil, fundErr(err)
			}
			if !sameWithdrawFundRequest(existing, order) {
				return nil, eerrs.ErrIdempotencyConflict.WrapMsg("业务单号已使用且参数不一致")
			}
			return existing, nil
		}
		return nil, fundErr(err)
	}
	if saved == nil {
		saved = order
	}
	return saved, nil
}

// SettleWithdrawFundOrder is retained for source compatibility. Payouts require the
// audited administrative review path and can no longer settle a pending request.
func (o *ChatDatabase) SettleWithdrawFundOrder(ctx context.Context, orderID, txID string, success bool) error {
	return errs.ErrArgs.WrapMsg("提现必须先审核并通过后台完成出款")
}

func (o *ChatDatabase) CreditFundDeposit(ctx context.Context, txID, userID, currency string, amount int64) (bool, error) {
	fresh := false
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		fresh = false
		now := time.Now()
		if err := o.fund.InsertChainTx(ctx, &chatdb.FundChainTx{TxID: txID, Direction: "deposit", UserID: userID, Currency: currency, Amount: amount, Confirmations: 1, CreatedAt: now}); err != nil {
			if fundDup(err) {
				return nil
			}
			return err
		}
		if err := o.fund.CreditAvailable(ctx, userID, currency, amount); err != nil {
			return err
		}
		if err := o.writeFundJournal(ctx, userID, currency, chatdb.FundBizDeposit, txID, amount, 0, now); err != nil {
			return err
		}
		fresh = true
		return nil
	})
	if err != nil {
		return false, err
	}
	return fresh, nil
}

func (o *ChatDatabase) GrantFundBalance(ctx context.Context, userID, clientOrderID string, amount int64) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		if _, err := o.fund.TakeOrderByClient(ctx, userID, clientOrderID); err == nil {
			return nil
		} else if !dbutil.IsDBNotFound(err) {
			return err
		}
		if err := o.fund.CreditAvailable(ctx, userID, chatdb.FundCurrencyBI99, amount); err != nil {
			return err
		}
		now := time.Now()
		id, err := newFundOrderID()
		if err != nil {
			return err
		}
		order := &chatdb.FundOrder{
			OrderID: id, ClientOrderID: clientOrderID, Biz: chatdb.FundBizGrant, Currency: chatdb.FundCurrencyBI99,
			SenderID: userID, RecvID: userID, Amount: amount, Status: chatdb.FundStatusDone, CreatedAt: now, MessageSent: true,
		}
		if err = o.fund.InsertOrder(ctx, order); err != nil {
			return err
		}
		return o.writeFundJournal(ctx, userID, chatdb.FundCurrencyBI99, chatdb.FundBizGrant, order.OrderID, amount, 0, now)
	})
}

func (o *ChatDatabase) ListUnsentFundOrders(ctx context.Context, limit int64) ([]*chatdb.FundOrder, error) {
	return o.fund.ListUnsent(ctx, limit)
}

func (o *ChatDatabase) MarkFundMessageSent(ctx context.Context, orderID string) error {
	return o.fund.MarkMessageSent(ctx, orderID)
}

func (o *ChatDatabase) ListPendingWithdrawals(ctx context.Context, limit int64) ([]*chatdb.FundOrder, error) {
	return o.fund.ListPendingWithdraw(ctx, limit)
}

func (o *ChatDatabase) writeFundJournal(ctx context.Context, userID, currency, biz, bizID string, available, frozen int64, now time.Time) error {
	return o.fund.InsertJournal(ctx, &chatdb.FundJournal{
		UserID: userID, Currency: currency, BizType: biz, BizID: bizID,
		AvailableDelta: available, FrozenDelta: frozen, CreatedAt: now,
	})
}

func newFundOrderID() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return "fo" + hex.EncodeToString(buf), nil
}

func itoa(n int32) string {
	if n == 0 {
		return "0"
	}
	var buf [12]byte
	i := len(buf)
	neg := n < 0
	u := n
	if neg {
		u = -n
	}
	for u > 0 {
		i--
		buf[i] = byte('0' + u%10)
		u /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
