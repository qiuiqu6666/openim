package interaction

import (
	"context"
	"errors"
	"github.com/openimsdk/tools/log"
	"net"
	"sync/atomic"
	"time"
)

type connectionTelemetry struct {
	attempts       atomic.Int64
	connectedAt    atomic.Int64
	lastPing       atomic.Int64
	lastPong       atomic.Int64
	lastMessage    atomic.Int64
	lastDisconnect atomic.Int64
}

func observedConnectionError(err error) string {
	var dns *net.DNSError
	if errors.As(err, &dns) {
		return "dns_error"
	}
	if errors.Is(err, context.Canceled) {
		return "session_cancelled"
	}
	var network net.Error
	if errors.As(err, &network) && network.Timeout() {
		return "transport_timeout"
	}
	return "transport_error"
}

func (m *connectionTelemetry) connected(ctx context.Context, background bool) {
	now := time.Now().UnixMilli()
	m.connectedAt.Store(now)
	m.lastPing.Store(0)
	m.lastPong.Store(0)
	m.lastMessage.Store(0)
	var recoveryMS int64
	if disconnected := m.lastDisconnect.Load(); disconnected > 0 {
		recoveryMS = now - disconnected
	}
	log.ZInfo(ctx, "connection_recovered", "connectedAtMs", now, "attempts", m.attempts.Swap(0), "recoveryMs", recoveryMS, "background", background)
}

func (m *connectionTelemetry) disconnected(ctx context.Context, err error, background bool) {
	now := time.Now().UnixMilli()
	m.lastDisconnect.Store(now)
	code, received := transportCloseCode(err)
	log.ZWarn(ctx, "connection_disconnected", err,
		"disconnectedAtMs", now, "connectedAtMs", m.connectedAt.Load(),
		"observedError", observedConnectionError(err), "confirmedReason", "unknown",
		"closeCode", code, "closeFrameReceived", received, "background", background,
		"lastPingAtMs", m.lastPing.Load(), "lastPongAtMs", m.lastPong.Load(), "lastMessageAtMs", m.lastMessage.Load())
}
