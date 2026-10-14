package interaction

import (
	"context"
	"net/http"
	"time"
)

// Optional interface preserves the existing JS and external transport contract.
func dialSession(ctx context.Context, conn LongConn, url string) (*http.Response, error) {
	if dialer, ok := conn.(interface {
		DialContext(context.Context, string, http.Header) (*http.Response, error)
	}); ok {
		return dialer.DialContext(ctx, url, nil)
	}
	return conn.Dial(url, nil)
}

func (c *LongConnMgr) recoverySignal() chan struct{} {
	c.recoveryMu.Lock()
	defer c.recoveryMu.Unlock()
	if c.recoveryWake == nil {
		c.recoveryWake = make(chan struct{}, 1)
	}
	return c.recoveryWake
}

func (c *LongConnMgr) wakeReconnect() {
	select {
	case c.recoverySignal() <- struct{}{}:
	default:
	}
}

func (c *LongConnMgr) waitReconnect(ctx context.Context, delay time.Duration) bool {
	// Until push coverage is deployed, retain a low-frequency background
	// fallback instead of cutting background reception off completely.
	if c.GetBackground() && delay < time.Minute {
		delay = time.Minute
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-c.recoverySignal():
		return ctx.Err() == nil
	case <-timer.C:
		return ctx.Err() == nil
	}
}

func (c *LongConnMgr) setCloseError(err error) {
	c.recoveryMu.Lock()
	defer c.recoveryMu.Unlock()
	c.closedErr = err
}
func (c *LongConnMgr) closeError() error {
	c.recoveryMu.Lock()
	defer c.recoveryMu.Unlock()
	return c.closedErr
}
