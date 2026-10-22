package file

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const uploadHKRegionalHost = "99chat-1416337673.cos.ap-hongkong.myqcloud.com"
const uploadHKAcceleratedHost = "99chat-1416337673.cos.accelerate.myqcloud.com"

func parseUploadURL(raw string) (*url.URL, error) { return url.Parse(raw) }

func (s *uploadRouteState) hongKong() bool {
	return s.multiBucket && (s.tier == 2 || s.tier == 3 || s.tier == 5)
}
func (s *uploadRouteState) lastTier() int {
	if s.multiBucket {
		return 5
	}
	return 2
}
func (s *uploadRouteState) relay() bool {
	return s.tier >= s.lastTier()-1 && (s.multiBucket || s.tier == 2)
}

func uploadName(name, user string, hk bool) string {
	name = strings.TrimPrefix(name, "/")
	name = strings.TrimPrefix(name, user+"/")
	if hk {
		name = "__cos_hk__/" + name
	}
	return user + "/" + name
}

// Failed hosts are avoided briefly, not disabled permanently. This cache belongs
// to one File uploader/session and stores neither credentials nor signed URLs.
type uploadCircuit struct {
	mu       sync.Mutex
	failures map[string]time.Time
}

func (c *uploadCircuit) blocked(key string) bool {
	if c == nil {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	until := c.failures[key]
	if !time.Now().Before(until) {
		delete(c.failures, key)
		return false
	}
	return true
}
func (c *uploadCircuit) mark(key string, failed bool) {
	if c == nil || key == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.failures == nil {
		c.failures = make(map[string]time.Time)
	}
	if failed {
		c.failures[key] = time.Now().Add(30 * time.Second)
	} else {
		delete(c.failures, key)
	}
}

func uploadBudget(req *UploadFileReq) time.Duration {
	image := strings.HasPrefix(req.ContentType, "image/")
	switch strings.ToLower(filepath.Ext(req.Filepath)) {
	case ".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif":
		image = true
	}
	if image {
		if source, err := Open(req); err == nil {
			size := source.Size()
			source.Close()
			if size <= 10<<20 {
				return 30 * time.Second
			}
		}
	}
	return 9 * time.Minute
}

type uploadProgressReader struct {
	io.Reader
	last *atomic.Int64
}

func (r uploadProgressReader) Read(p []byte) (int, error) {
	n, err := r.Reader.Read(p)
	if n > 0 {
		r.last.Store(time.Now().UnixNano())
	}
	return n, err
}

// Activity extends only the idle timer, never the caller's total deadline.
func uploadIdleContext(ctx context.Context, body io.Reader, idle time.Duration) (context.Context, io.Reader, func(), *atomic.Bool) {
	child, cancel := context.WithCancel(ctx)
	last := &atomic.Int64{}
	last.Store(time.Now().UnixNano())
	timedOut := &atomic.Bool{}
	done := make(chan struct{})
	go func() {
		defer close(done)
		timer := time.NewTicker(idle / 4)
		defer timer.Stop()
		for {
			select {
			case <-child.Done():
				return
			case <-timer.C:
				if time.Since(time.Unix(0, last.Load())) >= idle {
					timedOut.Store(true)
					cancel()
					return
				}
			}
		}
	}()
	return child, uploadProgressReader{body, last}, func() { cancel(); <-done }, timedOut
}

func uploadTransport(original http.RoundTripper) http.RoundTripper {
	if original == nil {
		original = http.DefaultTransport
	}
	if transport, ok := original.(*http.Transport); ok {
		tuned := transport.Clone()
		tuned.DialContext = (&net.Dialer{Timeout: 3 * time.Second, KeepAlive: 30 * time.Second}).DialContext
		tuned.TLSHandshakeTimeout = 3 * time.Second
		tuned.ResponseHeaderTimeout = 8 * time.Second
		return tuned
	}
	return original
}
