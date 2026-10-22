package fundswap

import (
	"context"
	"errors"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"math/big"
	"strings"

	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readconcern"
	"go.mongodb.org/mongo-driver/mongo/writeconcern"
)

func validateSubmission(user, clientID, from, to, amount string) (int64, error) {
	if user == "" || strings.TrimSpace(clientID) == "" || len(clientID) > 128 || precision(to) < 0 || from == to {
		return 0, ErrInvalid
	}
	return parseAmount(from, amount)
}

func (s *Store) orderByClient(ctx context.Context, user, clientID string) (*chatdb.FundOrder, error) {
	var order chatdb.FundOrder
	if err := s.collection("fund_order").FindOne(ctx, bson.M{"sender_id": user, "client_order_id": clientID}).Decode(&order); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return nil, nil
		}
		return nil, err
	}
	return &order, nil
}

func (s *Store) FindByClient(ctx context.Context, user, clientID string) (*chatdb.FundOrder, error) {
	if user == "" || strings.TrimSpace(clientID) == "" || len(clientID) > 128 {
		return nil, ErrInvalid
	}
	order, err := s.orderByClient(ctx, user, clientID)
	if err != nil {
		return nil, err
	}
	if order == nil || order.Biz != chatdb.FundBizSwap {
		return nil, ErrNotFound
	}
	return order, nil
}

// Idempotent returns nil,nil when no order exists. Reusing a business key with
// different immutable parameters always fails, including keys from other businesses.
func (s *Store) Idempotent(ctx context.Context, user, clientID, from, to, amount, quoteID string) (*chatdb.FundOrder, error) {
	minor, err := validateSubmission(user, clientID, from, to, amount)
	if err != nil {
		return nil, err
	}
	order, err := s.orderByClient(ctx, user, clientID)
	if err != nil || order == nil {
		return order, err
	}
	if order.Biz != chatdb.FundBizSwap || order.Currency != from || order.TargetCurrency != to || order.Amount != minor || order.SwapRequestQuoteID != quoteID {
		return nil, ErrConflict
	}
	return order, nil
}

func (s *Store) Submit(ctx context.Context, user, clientID, from, to, amount, quoteID string) (*chatdb.FundOrder, error) {
	minor, err := validateSubmission(user, clientID, from, to, amount)
	if err != nil {
		return nil, err
	}
	if order, err := s.Idempotent(ctx, user, clientID, from, to, amount, quoteID); err != nil || order != nil {
		return order, err
	}
	requestQuoteID := quoteID
	if quoteID == "" {
		quote, err := s.newQuote(ctx, user, from, to, amount)
		if err != nil {
			return nil, err
		}
		quoteID = quote.QuoteID
	}
	id, err := identifier("fo")
	if err != nil {
		return nil, err
	}
	session, err := s.DB.Client().StartSession()
	if err != nil {
		return nil, err
	}
	defer session.EndSession(ctx)
	var saved *chatdb.FundOrder
	for attempt := 0; attempt < 3; attempt++ {
		_, err = session.WithTransaction(ctx, func(sc mongo.SessionContext) (any, error) {
			if existing, e := s.Idempotent(sc, user, clientID, from, to, amount, requestQuoteID); e != nil || existing != nil {
				saved = existing
				return nil, e
			}
			var quote quoteRow
			if e := s.collection("fund_swap_quote").FindOne(sc, bson.M{"_id": quoteID, "user_id": user}).Decode(&quote); e != nil {
				if errors.Is(e, mongo.ErrNoDocuments) {
					return nil, ErrQuoteNotFound
				}
				return nil, e
			}
			if quote.FromCurrency != from || quote.ToCurrency != to || quote.MinorAmount != minor {
				return nil, ErrQuoteNotFound
			}
			if quote.UsedOrderID != "" {
				return nil, ErrQuoteUsed
			}
			now := s.clock()
			if quote.ExpiresAt <= now.UnixMilli() {
				return nil, ErrQuoteExpired
			}
			if quote.MinorReceived <= 0 {
				return nil, ErrInvalid
			}
			if e := fundsecurity.RunSpendGuard(sc); e != nil {
				return nil, e
			}
			if s.BeforeSubmit != nil {
				if e := s.BeforeSubmit(sc, user, from, minor); e != nil {
					return nil, e
				}
			}
			var source, target chatdb.FundAccount
			if e := s.collection("fund_account").FindOne(sc, bson.M{"user_id": user, "currency": from}).Decode(&source); e != nil {
				if errors.Is(e, mongo.ErrNoDocuments) {
					return nil, ErrInsufficientBalance
				}
				return nil, e
			}
			if source.Available < minor {
				return nil, ErrInsufficientBalance
			}
			if e := s.collection("fund_account").FindOne(sc, bson.M{"user_id": user, "currency": to}).Decode(&target); e != nil && !errors.Is(e, mongo.ErrNoDocuments) {
				return nil, e
			}
			after := new(big.Int).Add(big.NewInt(target.Available), big.NewInt(quote.MinorReceived))
			if !after.IsInt64() {
				return nil, ErrOverflow
			}
			consumed, e := s.collection("fund_swap_quote").UpdateOne(sc, bson.M{"_id": quoteID, "user_id": user, "used_order_id": "", "expires_at": bson.M{"$gt": now.UnixMilli()}}, bson.M{"$set": bson.M{"used_order_id": id}})
			if e != nil {
				return nil, e
			}
			if consumed.ModifiedCount != 1 {
				return nil, ErrQuoteUsed
			}
			debited, e := s.collection("fund_account").UpdateOne(sc, bson.M{"user_id": user, "currency": from, "available": bson.M{"$gte": minor}}, bson.M{"$inc": bson.M{"available": -minor}})
			if e != nil {
				return nil, e
			}
			if debited.MatchedCount != 1 {
				return nil, ErrInsufficientBalance
			}
			if _, e = s.collection("fund_account").UpdateOne(sc, bson.M{"user_id": user, "currency": to}, bson.M{"$inc": bson.M{"available": quote.MinorReceived}, "$setOnInsert": bson.M{"frozen": int64(0)}}, options.Update().SetUpsert(true)); e != nil {
				return nil, e
			}
			order := &chatdb.FundOrder{OrderID: id, ClientOrderID: clientID, Biz: chatdb.FundBizSwap, Scene: chatdb.FundSceneSingle, Currency: from, SenderID: user, RecvID: user, Amount: minor, TargetCurrency: to, TargetAmount: quote.MinorReceived, Status: chatdb.FundStatusDone, CreatedAt: now, MessageSent: true, QuoteID: quoteID, SwapRequestQuoteID: requestQuoteID, Rate: quote.Rate, MarketRate: quote.MarketRate, AdjustmentPercent: quote.AdjustmentPercent}
			if _, e = s.collection("fund_order").InsertOne(sc, order); e != nil {
				return nil, e
			}
			if _, e = s.collection("fund_journal").InsertMany(sc, []any{
				&chatdb.FundJournal{UserID: user, Currency: from, BizType: chatdb.FundBizSwap, BizID: id + ":out", AvailableDelta: -minor, BeforeAvailable: source.Available, AfterAvailable: source.Available - minor, CreatedAt: now},
				&chatdb.FundJournal{UserID: user, Currency: to, BizType: chatdb.FundBizSwap, BizID: id + ":in", AvailableDelta: quote.MinorReceived, BeforeAvailable: target.Available, AfterAvailable: after.Int64(), CreatedAt: now},
			}); e != nil {
				return nil, e
			}
			saved = order
			return nil, nil
		}, options.Transaction().SetReadConcern(readconcern.Snapshot()).SetWriteConcern(writeconcern.Majority()))
		if err == nil {
			return saved, nil
		}
		if !mongo.IsDuplicateKeyError(err) {
			return nil, err
		}
		// A concurrent submit can win the unique business key or target-account
		// upsert. Start a new snapshot and validate the same payload again.
		if existing, e := s.Idempotent(ctx, user, clientID, from, to, amount, requestQuoteID); e != nil || existing != nil {
			return existing, e
		}
	}
	return nil, err
}
