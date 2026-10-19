package interaction

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

func probeFixture(t *testing.T) (*LongConnMgr, *probeTransport) {
	c, transport := lifetimeManager(t)
	p := &probeTransport{lifetimeTransport: transport, pings: make(chan string, 8)}
	c.conn = p
	ctx, cancel := context.WithCancel(context.Background())
	c.probeContext = ctx
	t.Cleanup(cancel)
	return c, p
}

func TestForegroundProbeHalfOpenDeadline(t *testing.T) {
	c, p := probeFixture(t)
	c.probeForegroundConnection(40 * time.Millisecond)
	<-p.pings
	deadline := time.After(time.Second)
	for c.IsConnected() {
		select {
		case <-deadline:
			t.Fatal("half-open connection not retired")
		default:
			time.Sleep(time.Millisecond)
		}
	}
	if p.closes.Load() != 1 {
		t.Fatal("probe did not close exactly its old socket")
	}
}

func TestForegroundProbeIgnoresUnrelatedPong(t *testing.T) {
	c, p := probeFixture(t)
	c.probeForegroundConnection(40 * time.Millisecond)
	<-p.pings
	c.acknowledgeForegroundProbe("regular-heartbeat")
	time.Sleep(80 * time.Millisecond)
	if c.IsConnected() {
		t.Fatal("unrelated pong satisfied foreground probe")
	}
}

func TestForegroundProbeCancellationAndReplacement(t *testing.T) {
	for _, action := range []string{"background", "logout", "replacement", "pong"} {
		t.Run(action, func(t *testing.T) {
			c, p := probeFixture(t)
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			c.probeContext = ctx
			c.probeForegroundConnection(40 * time.Millisecond)
			token := <-p.pings
			for i := 0; i < 20; i++ {
				c.probeForegroundConnection(40 * time.Millisecond)
			}
			if len(p.pings) != 0 {
				t.Fatal("duplicate foreground probes")
			}
			switch action {
			case "background":
				c.SetBackground(true)
			case "logout":
				cancel()
			case "replacement":
				c.SetConnectionStatus(Closed)
				c.SetConnectionStatus(Connected)
			case "pong":
				c.acknowledgeForegroundProbe(token)
			}
			time.Sleep(80 * time.Millisecond)
			if p.closes.Load() != 0 || !c.IsConnected() {
				t.Fatal("obsolete probe closed connection")
			}
		})
	}
}

type probeTransport struct {
	*lifetimeTransport
	pings  chan string
	closes atomic.Int32
}

func (p *probeTransport) ForegroundPingWriter() func(string, time.Time) error {
	return func(token string, deadline time.Time) error { p.pings <- token; return nil }
}
func (p *probeTransport) SetReadDeadline(time.Duration) error { return nil }
func (p *probeTransport) Close() error                        { p.closes.Add(1); return nil }

func TestForegroundTransitionProbesConnectedSocketImmediately(t *testing.T) {
	c, transport := lifetimeManager(t)
	p := &probeTransport{lifetimeTransport: transport, pings: make(chan string, 8)}
	c.conn = p
	c.SetBackground(true)
	c.SetBackground(false)
	select {
	case token := <-p.pings:
		if err := c.pongHandler(token); err != nil {
			t.Fatal(err)
		}
	case <-time.After(300 * time.Millisecond):
		t.Fatal("foreground did not probe the supposedly connected socket; still waiting for heartbeat")
	}
	if !c.IsConnected() || p.closes.Load() != 0 {
		t.Fatal("healthy socket was closed")
	}
}

func TestForegroundReportProbesEvenWhenAlreadyMarkedForeground(t *testing.T) {
	c, p := probeFixture(t)
	c.SetBackground(false)
	select {
	case token := <-p.pings:
		c.acknowledgeForegroundProbe(token)
	case <-time.After(300 * time.Millisecond):
		t.Fatal("foreground report skipped probe because local visibility was already foreground")
	}
}
