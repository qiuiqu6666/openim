package chat

import (
	"context"
	"errors"
	table "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"github.com/openimsdk/chat/pkg/eerrs"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	livepb "github.com/openimsdk/chat/pkg/protocol/live"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/mongo"
	"testing"
	"time"
)

type spendSecurityDB struct{ *withdrawSecurityDB }

func (d *spendSecurityDB) TakeLiveSession(context.Context, string) (*table.LiveSession, error) {
	return &table.LiveSession{SessionID: "session", GroupID: "group", AnchorUserID: "bob", Status: table.LiveStatusLive}, nil
}
func (d *spendSecurityDB) TakeLiveTip(context.Context, string, string) (*table.LiveTip, error) {
	return nil, mongo.ErrNoDocuments
}

func TestAdditionalSpendsUseTransferSecurity(t *testing.T) {
	requests := []*pb.FundWithdrawalSecurityReq{
		{Packet: &pb.CreateFundPacketReq{ClientOrderID: "packet", Scene: "group", Biz: "packet_normal", Currency: "USDT", ShareAmount: "6", ShareCount: 2, GroupID: "group"}},
		{Swap: &pb.CreateFundSwapReq{ClientOrderID: "swap", FromCurrency: "USDT", ToCurrency: "TRX", Amount: "12", QuoteID: "quote"}},
		{Tip: &livepb.TipLiveReq{ClientOrderId: "tip", SessionID: "session", Currency: "USDT", Amount: 12000000}},
	}
	for _, req := range requests {
		t.Run(func() string {
			if req.Packet != nil {
				return "packet"
			}
			if req.Swap != nil {
				return "swap"
			}
			return "tip"
		}(), func(t *testing.T) {
			srv, db, security := newWithdrawalSecurityServer(t)
			srv.Database = &spendSecurityDB{db}
			srv.Swap = &swapServiceStub{}
			ctx := fundUserContext()
			security.status = &fundsecurity.Status{SMSRequired: true, Reasons: []string{"amount_threshold"}, SmsThreshold: "5"}
			check, err := srv.GetFundWithdrawalSecurity(ctx, req)
			if err != nil || !check.SmsRequired || security.subject.Amount != 12000000 || !security.subject.Transfer {
				t.Fatalf("incorrect scope: %+v %+v %v", check, security.subject, err)
			}
			order, err := srv.normalizeFundWithdrawalSecurityRequest(ctx, "alice", req)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = srv.secureFundSpend(ctx, "alice", order, "", ""); !errors.Is(err, eerrs.ErrFundWithdrawalSMSRequired) {
				t.Fatalf("missing SMS accepted: %v", err)
			}
			security.status = &fundsecurity.Status{CooldownUntil: time.Now().Add(time.Hour)}
			if _, err = srv.secureFundSpend(ctx, "alice", order, "id", "123456"); !errors.Is(err, eerrs.ErrFundWithdrawalCooldown) {
				t.Fatalf("cooldown accepted: %v", err)
			}
			security.status = withdrawalVerifiedStatus()
			guarded, err := srv.secureFundSpend(ctx, "alice", order, "", "")
			if err != nil {
				t.Fatal(err)
			}
			if err = fundsecurity.RunSpendGuard(guarded); !errors.Is(err, fundsecurity.ErrTransactionRequired) {
				t.Fatalf("nontransaction spend accepted: %v", err)
			}
			original := fundWithdrawalFingerprint(order)
			order.Amount++
			if original == fundWithdrawalFingerprint(order) {
				t.Fatal("amount not bound")
			}
			order.Amount--
			switch {
			case req.Packet != nil:
				order.ShareCount++
			case req.Swap != nil:
				order.QuoteID = "changed"
			case req.Tip != nil:
				order.ToAddress = "another-session"
			}
			if original == fundWithdrawalFingerprint(order) {
				t.Fatal("business identity not bound")
			}
		})
	}
}

func TestAdditionalSpendUnionRejectsAmbiguousPayload(t *testing.T) {
	srv, _, _ := newWithdrawalSecurityServer(t)
	_, err := srv.GetFundWithdrawalSecurity(fundUserContext(), &pb.FundWithdrawalSecurityReq{Packet: &pb.CreateFundPacketReq{}, Tip: &livepb.TipLiveReq{}})
	if !errors.Is(err, errs.ErrArgs) {
		t.Fatalf("mixed payload accepted: %v", err)
	}
}

func TestPacketSecurityUsesExactTotalAndRejectsOverflow(t *testing.T) {
	req := &pb.CreateFundPacketReq{ClientOrderID: "packet", Scene: "group", Biz: "packet_normal", Currency: "USDT", ShareAmount: "9223372036854", ShareCount: 2}
	if _, err := normalizeFundPacketSecurity("alice", req); err == nil {
		t.Fatal("overflow accepted")
	}
	req.ShareAmount = "0.000001"
	req.ShareCount = 3
	order, err := normalizeFundPacketSecurity("alice", req)
	if err != nil || order.Amount != 3 {
		t.Fatalf("wrong precision: %+v %v", order, err)
	}
}
