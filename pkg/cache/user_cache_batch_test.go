package cache

import (
	"context"
	"errors"
	"reflect"
	"testing"
)

func TestBatchFetchDeduplicatesMissingKeysAndReusesCache(t *testing.T) {
	calls := 0
	c := NewUserCache[string, string](func(v string) string { return v }, nil, nil, func(_ context.Context, keys []string) ([]string, error) {
		calls++
		if !reflect.DeepEqual(keys, []string{"missing"}) {
			t.Fatalf("duplicate query: %v", keys)
		}
		return keys, nil
	})
	c.Store("cached", "cached")
	for i := 0; i < 2; i++ {
		got, err := c.BatchFetch(context.Background(), []string{"cached", "missing", "missing", "cached"})
		if err != nil || !reflect.DeepEqual(got, map[string]string{"cached": "cached", "missing": "missing"}) {
			t.Fatalf("result=%v error=%v", got, err)
		}
	}
	if calls != 1 {
		t.Fatalf("backend calls=%d", calls)
	}
	if got, err := c.BatchFetch(context.Background(), nil); err != nil || len(got) != 0 || calls != 1 {
		t.Fatal("empty lookup accessed backend")
	}
}
func TestBatchFetchFailureCanRetry(t *testing.T) {
	want := errors.New("network failure")
	calls := 0
	c := NewUserCache[string, string](func(v string) string { return v }, nil, nil, func(_ context.Context, keys []string) ([]string, error) {
		calls++
		if calls == 1 {
			return nil, want
		}
		return keys, nil
	})
	if _, err := c.BatchFetch(context.Background(), []string{"missing", "missing"}); !errors.Is(err, want) {
		t.Fatalf("error=%v", err)
	}
	got, err := c.BatchFetch(context.Background(), []string{"missing"})
	if err != nil || got["missing"] != "missing" || calls != 2 {
		t.Fatalf("result=%v error=%v calls=%d", got, err, calls)
	}
}
