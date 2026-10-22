package fundsecurity

import "context"

type spendGuardKey struct{}

// WithSpendGuard carries a request-local guard into the ledger transaction.
// It never mutates shared service state or persists credentials.
func WithSpendGuard(ctx context.Context, guard func(context.Context) error) context.Context {
	return context.WithValue(ctx, spendGuardKey{}, guard)
}

// RunSpendGuard runs only for a new financial write, after idempotency recovery.
func RunSpendGuard(ctx context.Context) error {
	guard, _ := ctx.Value(spendGuardKey{}).(func(context.Context) error)
	if guard == nil {
		return nil
	}
	if !activeTransaction(ctx) {
		return ErrTransactionRequired
	}
	return guard(ctx)
}
