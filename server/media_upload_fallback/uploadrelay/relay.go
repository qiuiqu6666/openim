// Package uploadrelay provides a bounded authenticated streaming fallback for
// COS upload parts. It accepts only already signed requests to our regional bucket.
package uploadrelay

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/openimsdk/protocol/constant"
)

const TargetHeader = "X-Openim-Upload-Fallback"
const RegionalHost = "gz99chat-1416337673.cos.ap-guangzhou.myqcloud.com"
const HongKongHost = "99chat-1416337673.cos.ap-hongkong.myqcloud.com"
const MaxPartBytes int64 = 64 << 20

type Target struct {
	URL    string      `json:"url"`
	Header http.Header `json:"header"`
}

// COS validates the original short-lived PUT signature; the API additionally
// requires an IM session. No object credentials or arbitrary destinations enter.
func validate(raw string) (*url.URL, http.Header, bool) {
	var target Target
	if len(raw) == 0 || len(raw) > 16*1024 || json.Unmarshal([]byte(raw), &target) != nil {
		return nil, nil, false
	}
	u, err := url.Parse(target.URL)
	if err != nil || u.Scheme != "https" || (u.Host != RegionalHost && u.Host != HongKongHost) || u.User != nil || u.Fragment != "" || u.Opaque != "" {
		return nil, nil, false
	}
	if (!strings.HasPrefix(u.Path, "/chat/") && !strings.HasPrefix(u.Path, "/openim/")) || strings.Contains(u.Path, "..") {
		return nil, nil, false
	}
	for key := range target.Header {
		switch strings.ToLower(key) {
		case "host":
			if target.Header.Get(key) != u.Host {
				return nil, nil, false
			}
		case "authorization", "x-cos-security-token", "content-type", "content-md5":
		default:
			return nil, nil, false
		}
	}
	if !strings.Contains(target.Header.Get("Authorization"), "q-signature=") && u.Query().Get("q-signature") == "" {
		return nil, nil, false
	}
	return u, target.Header, true
}

func New(client *http.Client) gin.HandlerFunc {
	if client == nil {
		client = &http.Client{Timeout: 2 * time.Minute}
	}
	copyClient := *client
	copyClient.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	slots := make(chan struct{}, 16)
	return func(c *gin.Context) {
		if c.GetString(constant.OpUserID) == "" {
			c.Status(http.StatusUnauthorized)
			return
		}
		u, headers, ok := validate(c.GetHeader(TargetHeader))
		if !ok {
			c.Status(http.StatusBadRequest)
			return
		}
		size := c.Request.ContentLength
		if size <= 0 || size > MaxPartBytes {
			c.Status(http.StatusRequestEntityTooLarge)
			return
		}
		select {
		case slots <- struct{}{}:
			defer func() { <-slots }()
		default:
			c.Status(http.StatusTooManyRequests)
			return
		}
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Minute)
		defer cancel()
		body := http.MaxBytesReader(c.Writer, c.Request.Body, MaxPartBytes)
		defer body.Close()
		req, err := http.NewRequestWithContext(ctx, http.MethodPut, u.String(), body)
		if err != nil {
			c.Status(http.StatusBadRequest)
			return
		}
		req.Header, req.ContentLength = headers, size
		resp, err := copyClient.Do(req)
		if err != nil {
			c.Status(http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			// Never forward storage bodies, signed URLs or redirect locations.
			status := resp.StatusCode
			if status >= 300 && status < 400 {
				status = http.StatusBadGateway
			}
			c.Status(status)
			return
		}
		c.Status(http.StatusNoContent)
	}
}
