package interaction

import (
	"context"
	"errors"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/tools/log"
)

const foregroundProbeTimeout = 3 * time.Second

// Optional: browser/custom transports retain their existing heartbeat policy.
type foregroundPingTransport interface {
	ForegroundPingWriter() func(string, time.Time) error
}

type foregroundProbe struct {
	token      string
	connection <-chan struct{}
	ack        chan struct{}
	cancel     chan struct{}
	started    time.Time
}

func (c *LongConnMgr) cancelForegroundProbeLocked() {
	if p := c.foregroundProbe; p != nil {
		close(p.cancel)
		c.foregroundProbe = nil
	}
}

func (c *LongConnMgr) acknowledgeForegroundProbe(token string) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	if p := c.foregroundProbe; p != nil && p.token == token {
		select {
		case p.ack <- struct{}{}:
		default:
		}
	}
}

func (c *LongConnMgr) probeForegroundConnection(timeout time.Duration) {
	transport, supported := c.conn.(foregroundPingTransport)
	if !supported {
		return
	}
	// Same lock order as close(): connection state, then visibility. A dial
	// changes state to Connecting before replacing the underlying socket.
	c.w.Lock()
	if c.connStatus != Connected {
		c.w.Unlock()
		return
	}
	c.mutex.Lock()
	if c.IsBackground {
		c.mutex.Unlock()
		c.w.Unlock()
		return
	}
	if c.connectionDone == nil {
		c.connectionDone = make(chan struct{})
	}
	if p := c.foregroundProbe; p != nil && p.connection == c.connectionDone {
		c.mutex.Unlock()
		c.w.Unlock()
		return
	}
	c.cancelForegroundProbeLocked()
	writePing := transport.ForegroundPingWriter() // captures this socket, never a later one
	p := &foregroundProbe{token: "foreground-" + utils.OperationIDGenerator(), connection: c.connectionDone,
		ack: make(chan struct{}, 1), cancel: make(chan struct{}), started: time.Now()}
	c.foregroundProbe = p
	ctx := c.probeContext
	if ctx == nil {
		ctx = context.Background()
	}
	c.mutex.Unlock()
	c.w.Unlock()
	log.ZInfo(ctx, "foreground_probe_started", "timeoutMs", timeout.Milliseconds())
	go c.runForegroundProbe(ctx, p, writePing, timeout)
}

func (c *LongConnMgr) runForegroundProbe(ctx context.Context, p *foregroundProbe, writePing func(string, time.Time) error, timeout time.Duration) {
	defer func() {
		c.mutex.Lock()
		if c.foregroundProbe == p {
			c.foregroundProbe = nil
		}
		c.mutex.Unlock()
	}()
	select {
	case <-ctx.Done():
		return
	case <-p.cancel:
		return
	case <-p.connection:
		return
	default:
	}
	deadline := p.started.Add(timeout)
	err := writePing(p.token, deadline)
	if err == nil {
		timer := time.NewTimer(time.Until(deadline))
		defer timer.Stop()
		select {
		case <-ctx.Done():
			return
		case <-p.cancel:
			return
		case <-p.connection:
			return
		case <-p.ack:
			log.ZInfo(ctx, "foreground_probe_confirmed", "elapsedMs", time.Since(p.started).Milliseconds())
			return
		case <-timer.C:
			err = errors.New("foreground pong deadline exceeded")
		}
	}
	if c.retireForegroundConnection(ctx, p, err) {
		log.ZInfo(ctx, "foreground_probe_reconnect", "elapsedMs", time.Since(p.started).Milliseconds())
		c.wakeReconnect()
	}
}

func (c *LongConnMgr) retireForegroundConnection(ctx context.Context, p *foregroundProbe, reason error) bool {
	c.w.Lock()
	defer c.w.Unlock()
	c.mutex.Lock()
	defer c.mutex.Unlock()
	if ctx.Err() != nil || c.IsBackground || c.foregroundProbe != p || c.connStatus != Connected || c.connectionDone != p.connection {
		return false
	}
	// A pong arriving as the timer fires wins over timeout.
	select {
	case <-p.ack:
		return false
	default:
	}
	c.foregroundProbe = nil
	c.connStatus = Closed
	c.endConnectionRequestsLocked()
	c.setCloseError(reason)
	c.metrics.disconnected(ctx, reason, false)
	_ = c.conn.Close()
	return true
}
