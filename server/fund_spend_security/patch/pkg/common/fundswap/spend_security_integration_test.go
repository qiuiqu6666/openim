//go:build integration

package fundswap

import (
	"context"
	"errors"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"testing"
	"time"
)

func TestSwapSecurityProofCommitsWithLedger(t *testing.T) {
	s, ctx := fixture(t)
	account(t, s, ctx, "alice", "USDT", 10000000)
	security, err := fundsecurity.NewWithPrefix(ctx, s.DB, s.CollectionPrefix)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, name := range []string{"fund_withdraw_security_config", "fund_withdraw_security_user", "fund_withdraw_security_device", "fund_withdraw_security_challenge"} {
			s.collection(name).Drop(context.Background())
		}
	})
	cfg, err := security.GetConfig(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for i := range cfg.Thresholds {
		cfg.Thresholds[i].SmsThreshold = "0"
	}
	if err = security.PutConfig(ctx, cfg); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	sub := fundsecurity.Subject{UserID: "alice", DeviceID: "device", PlatformID: 2, Phone: "+86 13800000000", Transfer: true, Fingerprint: "swap-request", Currency: "USDT", Amount: 1000000}
	challenge, code, err := security.CreateChallenge(ctx, sub, now)
	if err != nil {
		t.Fatal(err)
	}
	if err = security.SetChallengeSent(ctx, challenge.ID); err != nil {
		t.Fatal(err)
	}
	q, err := s.Quote(ctx, "alice", "USDT", "TRX", "1")
	if err != nil {
		t.Fatal(err)
	}
	guarded := fundsecurity.WithSpendGuard(ctx, func(tx context.Context) error { return security.Guard(tx, sub, challenge.ID, code, now) })
	rejected := errors.New("later ledger failure")
	s.BeforeSubmit = func(context.Context, string, string, int64) error { return rejected }
	if _, err = s.Submit(guarded, "alice", "swap", "USDT", "TRX", "1", q.QuoteID); !errors.Is(err, rejected) {
		t.Fatalf("expected rollback: %v", err)
	}
	if available(t, s, ctx, "alice", "USDT") != 10000000 {
		t.Fatal("failed swap debited")
	}
	if err = security.VerifyChallenge(ctx, sub, challenge.ID, code, now); err != nil {
		t.Fatalf("rollback consumed SMS: %v", err)
	}
	s.BeforeSubmit = nil
	first, err := s.Submit(guarded, "alice", "swap", "USDT", "TRX", "1", q.QuoteID)
	if err != nil {
		t.Fatal(err)
	}
	if err = security.VerifyChallenge(ctx, sub, challenge.ID, code, now); !errors.Is(err, fundsecurity.ErrCodeUsed) {
		t.Fatalf("SMS replay allowed: %v", err)
	}
	denied := fundsecurity.WithSpendGuard(ctx, func(context.Context) error { return rejected })
	retry, err := s.Submit(denied, "alice", "swap", "USDT", "TRX", "1", q.QuoteID)
	if err != nil || retry.OrderID != first.OrderID {
		t.Fatalf("retry failed: %v", err)
	}
	if available(t, s, ctx, "alice", "USDT") != 9000000 {
		t.Fatal("duplicate debit")
	}
}
