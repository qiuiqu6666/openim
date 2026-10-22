//go:build integration

package fundswap

import (
	"context"
	"errors"
	"fmt"
	"math"
	"math/big"
	"os"
	"sync"
	"testing"
	"time"

	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gopkg.in/yaml.v3"
)

func fixture(t *testing.T) (*Store, context.Context) {
	t.Helper()
	var cfg struct {
		URI      string `yaml:"uri"`
		Database string `yaml:"database"`
	}
	cfg.URI, cfg.Database = os.Getenv("WITHDRAW_TEST_MONGO_URI"), os.Getenv("WITHDRAW_TEST_MONGO_DB")
	if cfg.URI == "" || cfg.Database == "" {
		raw, err := os.ReadFile("../../../../.runtime/chat/config/mongodb.yml")
		if err != nil {
			t.Fatal(err)
		}
		if err = yaml.Unmarshal(raw, &cfg); err != nil {
			t.Fatal(err)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	client, err := mongo.Connect(ctx, options.Client().ApplyURI(cfg.URI))
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	s := &Store{DB: client.Database(cfg.Database), CollectionPrefix: fmt.Sprintf("swap_test_%d_", time.Now().UnixNano()), prices: func(_ context.Context, now time.Time) prices {
		return prices{usd: big.NewRat(7, 1), trx: big.NewRat(1, 3), usdAt: &now, trxAt: &now, trxMarketAt: now.UnixMilli()}
	}}
	if err = s.initialize(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, name := range []string{"fund_account", "fund_order", "fund_journal", "fund_swap_quote", "fund_swap_config"} {
			s.collection(name).Drop(context.Background())
		}
		client.Disconnect(context.Background())
		cancel()
	})
	return s, ctx
}

func account(t *testing.T, s *Store, ctx context.Context, user, currency string, amount int64) {
	t.Helper()
	_, err := s.collection("fund_account").InsertOne(ctx, &chatdb.FundAccount{UserID: user, Currency: currency, Available: amount})
	if err != nil {
		t.Fatal(err)
	}
}

func available(t *testing.T, s *Store, ctx context.Context, user, currency string) int64 {
	t.Helper()
	var row chatdb.FundAccount
	err := s.collection("fund_account").FindOne(ctx, bson.M{"user_id": user, "currency": currency}).Decode(&row)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return 0
	}
	if err != nil {
		t.Fatal(err)
	}
	return row.Available
}

func TestQuoteLocksSpreadAndIdempotencyAfterExpiry(t *testing.T) {
	s, ctx := fixture(t)
	account(t, s, ctx, "alice", "USDT", 10000000)
	c, err := s.GetConfig(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for i := range c.Pairs {
		if c.Pairs[i].FromCurrency == "USDT" && c.Pairs[i].ToCurrency == "TRX" {
			c.Pairs[i].AdjustmentPercent = "-3.333333"
		}
	}
	if _, err = s.PutConfig(ctx, "admin", c.Pairs); err != nil {
		t.Fatal(err)
	}
	quote, err := s.Quote(ctx, "alice", "USDT", "TRX", "1")
	if err != nil || quote.EstimatedReceived != "2.9" {
		t.Fatalf("%+v %v", quote, err)
	}
	// Administrative changes affect future quotes, never the locked contract.
	for i := range c.Pairs {
		c.Pairs[i].AdjustmentPercent = "50"
	}
	if _, err = s.PutConfig(ctx, "admin", c.Pairs); err != nil {
		t.Fatal(err)
	}
	order, err := s.Submit(ctx, "alice", "swap_lock", "USDT", "TRX", "1", quote.QuoteID)
	if err != nil || order.TargetAmount != 2900000 || order.Rate != quote.Rate {
		t.Fatalf("%+v %v", order, err)
	}
	if available(t, s, ctx, "alice", "USDT") != 9000000 || available(t, s, ctx, "alice", "TRX") != 2900000 {
		t.Fatal("wrong posted balances")
	}
	// Both zero and nonzero before/after values must be stored, not omitted.
	var journals []bson.M
	cur, err := s.collection("fund_journal").Find(ctx, bson.M{"user_id": "alice"})
	if err != nil {
		t.Fatal(err)
	}
	if err = cur.All(ctx, &journals); err != nil {
		t.Fatal(err)
	}
	if len(journals) != 2 {
		t.Fatal(len(journals))
	}
	for _, j := range journals {
		if _, ok := j["before_available"]; !ok {
			t.Fatal("missing before", j)
		}
		if _, ok := j["after_available"]; !ok {
			t.Fatal("missing after", j)
		}
	}
	s.now = func() time.Time { return time.UnixMilli(quote.ExpiresAt).Add(time.Minute) }
	s.prices = func(context.Context, time.Time) prices { return prices{} }
	for i := 0; i < 3; i++ {
		again, err := s.Submit(ctx, "alice", "swap_lock", "USDT", "TRX", "1.000000", quote.QuoteID)
		if err != nil || again.OrderID != order.OrderID {
			t.Fatal("retry failed", again, err)
		}
	}
	if _, err = s.Submit(ctx, "alice", "swap_lock", "USDT", "TRX", "2", quote.QuoteID); !errors.Is(err, ErrConflict) {
		t.Fatal("changed payload accepted", err)
	}
	if _, err = s.Submit(ctx, "alice", "swap_reuse", "USDT", "TRX", "1", quote.QuoteID); !errors.Is(err, ErrQuoteUsed) {
		t.Fatal("used quote accepted", err)
	}
	if available(t, s, ctx, "alice", "USDT") != 9000000 {
		t.Fatal("retry debited funds")
	}
	if found, err := s.FindByClient(ctx, "alice", "swap_lock"); err != nil || found.OrderID != order.OrderID {
		t.Fatal(found, err)
	}
	if _, err = s.FindByClient(ctx, "bob", "swap_lock"); !errors.Is(err, ErrNotFound) {
		t.Fatal("cross-user lookup", err)
	}
}

func TestExpiredWrongOwnerAndOverflowDoNotDebit(t *testing.T) {
	s, ctx := fixture(t)
	account(t, s, ctx, "alice", "USDT", 10000000)
	account(t, s, ctx, "alice", "TRX", math.MaxInt64)
	quote, err := s.Quote(ctx, "alice", "USDT", "TRX", "1")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.Submit(ctx, "bob", "swap_other", "USDT", "TRX", "1", quote.QuoteID); !errors.Is(err, ErrQuoteNotFound) {
		t.Fatal("other owner quote accepted", err)
	}
	if _, err = s.Submit(ctx, "alice", "swap_wrong", "USDT", "TRX", "2", quote.QuoteID); !errors.Is(err, ErrQuoteNotFound) {
		t.Fatal("changed quote amount", err)
	}
	if _, err = s.Submit(ctx, "alice", "swap_overflow", "USDT", "TRX", "1", quote.QuoteID); !errors.Is(err, ErrOverflow) {
		t.Fatal("overflow not caught", err)
	}
	var q quoteRow
	if err = s.collection("fund_swap_quote").FindOne(ctx, bson.M{"_id": quote.QuoteID}).Decode(&q); err != nil || q.UsedOrderID != "" {
		t.Fatal("failed submit consumed quote", err)
	}
	s.now = func() time.Time { return time.UnixMilli(quote.ExpiresAt) }
	if _, err = s.Submit(ctx, "alice", "swap_expired", "USDT", "TRX", "1", quote.QuoteID); !errors.Is(err, ErrQuoteExpired) {
		t.Fatal("expired quote accepted", err)
	}
	if available(t, s, ctx, "alice", "USDT") != 10000000 {
		t.Fatal("rejected trade debited funds")
	}
	n, err := s.collection("fund_order").CountDocuments(ctx, bson.M{})
	if err != nil || n != 0 {
		t.Fatal("rejected trade created order", n, err)
	}
}

func TestLiveRedisPricesForAllSixPairs(t *testing.T) {
	s, ctx := fixture(t)
	raw, err := os.ReadFile("../../../../.runtime/chat/config/redis.yml")
	if err != nil {
		t.Fatal(err)
	}
	var cfg struct {
		Address  []string `yaml:"address"`
		Username string   `yaml:"username"`
		Password string   `yaml:"password"`
		DB       int      `yaml:"db"`
	}
	if err = yaml.Unmarshal(raw, &cfg); err != nil {
		t.Fatal(err)
	}
	if len(cfg.Address) == 0 {
		t.Fatal("missing Redis address")
	}
	rdb := redis.NewClient(&redis.Options{Addr: cfg.Address[0], Username: cfg.Username, Password: cfg.Password, DB: cfg.DB, ReadTimeout: 2 * time.Second, WriteTimeout: 2 * time.Second})
	defer rdb.Close()
	s.Redis, s.prices = rdb, nil
	for _, pair := range defaultConfig().Pairs {
		quote, err := s.Quote(ctx, "isolated-live-test", pair.FromCurrency, pair.ToCurrency, "1")
		if err != nil {
			t.Fatalf("%s/%s: %v", pair.FromCurrency, pair.ToCurrency, err)
		}
		var row quoteRow
		if err = s.collection("fund_swap_quote").FindOne(ctx, bson.M{"_id": quote.QuoteID}).Decode(&row); err != nil {
			t.Fatal(err)
		}
		if (pair.FromCurrency == "BI99" || pair.ToCurrency == "BI99") && (row.USDCNYFetchedAt == nil || !fresh(s.clock(), *row.USDCNYFetchedAt, 15*time.Minute)) {
			t.Fatal("missing/stale fiat snapshot")
		}
		if (pair.FromCurrency == "TRX" || pair.ToCurrency == "TRX") && (row.TRXUSDTFetchedAt == nil || !fresh(s.clock(), *row.TRXUSDTFetchedAt, 2*time.Minute) || !fresh(s.clock(), time.UnixMilli(row.TRXMarketAt), 2*time.Minute)) {
			t.Fatal("missing/stale crypto snapshot")
		}
		if quote.EstimatedReceived == "0" || quote.InputValueUsd == nil {
			t.Fatal("unusable live quote")
		}
		t.Logf("%s/%s marketRate=%s rate=%s", pair.FromCurrency, pair.ToCurrency, quote.MarketRate, quote.Rate)
	}
	if n, err := s.collection("fund_account").CountDocuments(ctx, bson.M{}); err != nil || n != 0 {
		t.Fatal("quote mutated account", n, err)
	}
}

func TestConcurrentClientRetriesAndQuoteConsumption(t *testing.T) {
	s, ctx := fixture(t)
	account(t, s, ctx, "alice", "USDT", 10000000)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var ids []string
	var failures []error
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			order, err := s.Submit(ctx, "alice", "same_client", "USDT", "TRX", "1", "")
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				failures = append(failures, err)
			} else {
				ids = append(ids, order.OrderID)
			}
		}()
	}
	wg.Wait()
	if len(failures) != 0 || len(ids) != 8 {
		t.Fatal(ids, failures)
	}
	for _, id := range ids {
		if id != ids[0] {
			t.Fatal("duplicate client orders", ids)
		}
	}
	if available(t, s, ctx, "alice", "USDT") != 9000000 {
		t.Fatal("duplicate client debit")
	}
	quote, err := s.Quote(ctx, "alice", "USDT", "TRX", "1")
	if err != nil {
		t.Fatal(err)
	}
	ids, failures = nil, nil
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			order, err := s.Submit(ctx, "alice", fmt.Sprintf("unique_client_%d", i), "USDT", "TRX", "1", quote.QuoteID)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				failures = append(failures, err)
			} else {
				ids = append(ids, order.OrderID)
			}
		}(i)
	}
	wg.Wait()
	if len(ids) != 1 || len(failures) != 5 {
		t.Fatal("quote raced", ids, failures)
	}
	for _, err := range failures {
		if !errors.Is(err, ErrQuoteUsed) {
			t.Fatal(err)
		}
	}
	if available(t, s, ctx, "alice", "USDT") != 8000000 {
		t.Fatal("duplicate quote debit")
	}
	n, err := s.collection("fund_journal").CountDocuments(ctx, bson.M{})
	if err != nil || n != 4 {
		t.Fatal("duplicate journals", n, err)
	}
}

func TestBeforeSubmitIsTransactionalAndBusinessKeyCannotCrossBusiness(t *testing.T) {
	s, ctx := fixture(t)
	account(t, s, ctx, "alice", "USDT", 10000000)
	_, err := s.collection("fund_order").InsertOne(ctx, &chatdb.FundOrder{OrderID: "transfer_order", ClientOrderID: "transfer_key", SenderID: "alice", Biz: chatdb.FundBizTransfer, Amount: 1000000, Currency: "USDT"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.Submit(ctx, "alice", "transfer_key", "USDT", "TRX", "1", ""); !errors.Is(err, ErrConflict) {
		t.Fatal("cross-business key accepted", err)
	}
	limitErr := errors.New("test daily limit")
	s.BeforeSubmit = func(ctx context.Context, user, currency string, amount int64) error {
		if mongo.SessionFromContext(ctx) == nil {
			return errors.New("limit check lacks transaction")
		}
		n, err := s.collection("fund_order").CountDocuments(ctx, bson.M{"sender_id": user, "biz": chatdb.FundBizSwap})
		if err != nil {
			return err
		}
		if n >= 1 {
			return limitErr
		}
		return nil
	}
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, err := s.Submit(ctx, "alice", fmt.Sprintf("limit_%d", i), "USDT", "TRX", "1", "")
			results <- err
		}(i)
	}
	wg.Wait()
	close(results)
	success, denied := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, limitErr) {
			denied++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || denied != 1 || available(t, s, ctx, "alice", "USDT") != 9000000 {
		t.Fatal("daily limit raced", success, denied)
	}
}

func TestLateJournalFailureRollsBackBothAccountsOrderAndQuote(t *testing.T) {
	s, ctx := fixture(t)
	account(t, s, ctx, "alice", "USDT", 10000000)
	quote, err := s.Quote(ctx, "alice", "USDT", "TRX", "1")
	if err != nil {
		t.Fatal(err)
	}
	// This isolated fixture intentionally rejects the outgoing journal after all
	// account updates and the order insert have already occurred in the callback.
	if err = s.collection("fund_journal").Drop(ctx); err != nil {
		t.Fatal(err)
	}
	err = s.DB.CreateCollection(ctx, s.CollectionPrefix+"fund_journal", options.CreateCollection().SetValidator(bson.M{"available_delta": bson.M{"$gte": 0}}).SetValidationLevel("strict"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.Submit(ctx, "alice", "late_failure", "USDT", "TRX", "1", quote.QuoteID); err == nil {
		t.Fatal("invalid journal did not abort")
	}
	if available(t, s, ctx, "alice", "USDT") != 10000000 || available(t, s, ctx, "alice", "TRX") != 0 {
		t.Fatal("late failure changed balances")
	}
	for _, name := range []string{"fund_order", "fund_journal"} {
		n, err := s.collection(name).CountDocuments(ctx, bson.M{})
		if err != nil || n != 0 {
			t.Fatal("late failure persisted", name, n, err)
		}
	}
	var row quoteRow
	if err = s.collection("fund_swap_quote").FindOne(ctx, bson.M{"_id": quote.QuoteID}).Decode(&row); err != nil || row.UsedOrderID != "" {
		t.Fatal("late failure consumed quote", err)
	}
}
