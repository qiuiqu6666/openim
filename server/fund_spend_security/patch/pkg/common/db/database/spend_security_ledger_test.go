package database

import (
	"context"
	"errors"
	model "github.com/openimsdk/chat/pkg/common/db/model/chat"
	table "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"github.com/openimsdk/chat/pkg/eerrs"
	"go.mongodb.org/mongo-driver/bson"
	"testing"
	"time"
)

func TestAdditionalSpendGuardRollbackAndRetry(t *testing.T) {
	for _, kind := range []string{"packet_normal", "packet_exclusive", "live_tip"} {
		t.Run(kind, func(t *testing.T) {
			f := newWithdrawFixture(t)
			if err := f.store.fund.CreditAvailable(f.ctx, "user", "USDT", 1000); err != nil {
				t.Fatal(err)
			}
			if kind == "live_tip" {
				// Dedicated database: the live model has no collection prefix support.
				liveDB := f.db.Client().Database(f.prefix + "live")
				t.Cleanup(func() {
					if err := liveDB.Drop(context.Background()); err != nil {
						t.Error(err)
					}
				})
				var err error
				f.store.live, err = model.NewLive(liveDB)
				if err != nil {
					t.Fatal(err)
				}
				_, err = liveDB.Collection("live_session").InsertOne(f.ctx, &table.LiveSession{SessionID: "session", GroupID: "group", AnchorUserID: "recipient", Status: table.LiveStatusLive})
				if err != nil {
					t.Fatal(err)
				}
			}
			request := func() *table.FundOrder {
				return &table.FundOrder{SenderID: "user", RecvID: "recipient", ClientOrderID: "client", Biz: kind, Scene: "group", Currency: "USDT", Amount: 100, ShareCount: 2, ShareAmount: 50}
			}
			submit := func(ctx context.Context) error {
				if kind == "live_tip" {
					_, err := f.store.CreateLiveTip(ctx, "user", "client", "session", "recipient", "USDT", "", "hash", 100, time.Now())
					return err
				}
				if kind == "packet_normal" {
					_, err := f.store.CreatePacketFundOrder(ctx, request(), []int64{50, 50})
					return err
				}
				_, err := f.store.CreateDirectFundOrder(ctx, request())
				return err
			}
			reject := errors.New("security rejected")
			guarded := fundsecurity.WithSpendGuard(f.ctx, func(context.Context) error { return reject })
			if err := submit(guarded); !errors.Is(err, reject) {
				t.Fatalf("guard bypass: %v", err)
			}
			f.balance(t, "user", 1000, 0)
			f.count(t, "fund_order", bson.M{}, 0)
			calls := 0
			allowed := fundsecurity.WithSpendGuard(f.ctx, func(context.Context) error { calls++; return nil })
			if err := submit(allowed); err != nil {
				t.Fatal(err)
			}
			if calls < 1 {
				t.Fatal("guard not called")
			}
			if err := submit(guarded); err != nil {
				t.Fatalf("committed retry rejected: %v", err)
			}
			frozen := int64(0)
			if kind == "packet_normal" {
				frozen = 100
			}
			f.balance(t, "user", 900, frozen)
			f.count(t, "fund_order", bson.M{}, 1)
			if kind == "packet_normal" {
				changed := request()
				changed.Amount = 200
				if _, err := f.store.CreatePacketFundOrder(allowed, changed, []int64{100, 100}); !errors.Is(err, eerrs.ErrIdempotencyConflict) {
					t.Fatalf("changed retry accepted: %v", err)
				}
			}
		})
	}
}
