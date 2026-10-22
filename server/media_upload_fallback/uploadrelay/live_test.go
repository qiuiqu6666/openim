package uploadrelay

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/openimsdk/open-im-server/v3/pkg/common/config"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/objectstorage"
	"github.com/openimsdk/protocol/constant"
)

// Explicit opt-in; writes only random diagnostic keys, then deletes them.
// The relay uses a local authenticated-handler fixture, not a real user's token.
func TestLiveCOSUploadFallback(t *testing.T) {
	path := os.Getenv("UPLOAD_FALLBACK_LIVE_CONFIG")
	if path == "" {
		t.Skip("live configuration required")
	}
	var cfg struct {
		Object struct {
			Cos config.Cos `mapstructure:"cos"`
		} `mapstructure:"object"`
	}
	if err := config.LoadConfig(path, "UPLOAD_FALLBACK_LIVE", &cfg); err != nil {
		t.Fatal("configuration unavailable")
	}
	regionalHost := RegionalHost
	if os.Getenv("UPLOAD_FALLBACK_LIVE_HK") == "1" {
		if cfg.Object.Cos.Legacy == nil {
			t.Fatal("backup configuration unavailable")
		}
		cfg.Object.Cos = *cfg.Object.Cos.Legacy
		cfg.Object.Cos.BucketURL = "https://99chat-1416337673.cos.accelerate.myqcloud.com"
		regionalHost = HongKongHost
	}
	backend, err := objectstorage.NewCOS(*cfg.Object.Cos.Build(), "")
	if err != nil {
		t.Fatal("storage initialization failed")
	}
	client := &http.Client{Timeout: 30 * time.Second}
	for _, tier := range []string{"primary", "regional", "relay"} {
		t.Run(tier, func(t *testing.T) {
			key := fmt.Sprintf("chat/temp/upload-fallback-check/%d-%s", time.Now().UnixNano(), tier)
			defer func() {
				if err := backend.DeleteObject(context.Background(), key); err != nil {
					t.Error("diagnostic cleanup failed")
				}
			}()
			payload := []byte("upload-fallback-integrity-" + key)
			sign, err := backend.PresignedPutObject(context.Background(), key, time.Minute, nil)
			if err != nil {
				t.Fatal("signing failed")
			}
			metadata := sign.Header.Get(TargetHeader)
			var target Target
			if json.Unmarshal([]byte(metadata), &target) != nil || metadata == "" {
				t.Fatal("missing origin signature")
			}
			if tier == "relay" {
				w := httptest.NewRecorder()
				c, _ := gin.CreateTestContext(w)
				c.Set(constant.OpUserID, "isolated-upload-test")
				c.Request = httptest.NewRequest("POST", "/object/upload_relay", bytes.NewReader(payload))
				c.Request.Header.Set(TargetHeader, metadata)
				New(client)(c)
				c.Writer.WriteHeaderNow()
				if w.Code != 204 {
					t.Fatalf("relay status %d", w.Code)
				}
			} else {
				raw, header := sign.URL, sign.Header
				if tier == "regional" {
					raw, header = target.URL, target.Header
				}
				req, _ := http.NewRequest("PUT", raw, bytes.NewReader(payload))
				req.Header = header
				resp, err := client.Do(req)
				if err != nil {
					t.Fatal("direct upload transport failed")
				}
				io.Copy(io.Discard, resp.Body)
				resp.Body.Close()
				if resp.StatusCode != 200 {
					t.Fatalf("direct upload status %d", resp.StatusCode)
				}
			}
			resp, err := client.Get("https://" + regionalHost + "/" + key)
			if err != nil {
				t.Fatal("verification read failed")
			}
			body, err := io.ReadAll(resp.Body)
			resp.Body.Close()
			if err != nil || resp.StatusCode != 200 || !bytes.Equal(body, payload) {
				t.Fatal("stored bytes differ")
			}
		})
	}
}
