package interaction

import (
	"math/rand"
	"time"
)

type ReconnectStrategy interface {
	GetSleepInterval() time.Duration
	Reset()
}

type ExponentialRetry struct {
	attempts []int
	index    int
}

func NewExponentialRetry() *ExponentialRetry {
	return &ExponentialRetry{
		attempts: []int{1, 2, 4, 8, 16, 30},
		index:    -1,
	}
}

func (rs *ExponentialRetry) GetSleepInterval() time.Duration {
	if rs.index < len(rs.attempts)-1 {
		rs.index++
	}
	base := time.Second * time.Duration(rs.attempts[rs.index])
	// Never wrap back to fast retries during a sustained outage. Equal jitter
	// spreads reconnects while retaining a minimum delay at the capped stage.
	return base/2 + time.Duration(rand.Int63n(int64(base/2)+1))
}

func (rs *ExponentialRetry) Reset() {
	rs.index = -1
}
