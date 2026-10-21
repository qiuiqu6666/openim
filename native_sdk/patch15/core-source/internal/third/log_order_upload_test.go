package third

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/internal/third/file"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

type orderedLogProgress struct{}

func (orderedLogProgress) OnProgress(int64, int64) {}

func TestLogUploadMixedNamesArchive(t *testing.T) {
	for _, lines := range []int{10000, 0} {
		t.Run(map[bool]string{true: "all", false: "recent"}[lines == 0], func(t *testing.T) {
			dir := t.TempDir()
			for name, body := range map[string]string{"open-im-sdk-core.2026-10-20": "old", "chat-sdk-core.2026-10-21": "latest-video-failure"} {
				if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0600); err != nil {
					t.Fatal(err)
				}
			}
			var address string
			var uploaded []byte
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var data any
				switch r.URL.Path {
				case "/object/part_limit":
					data = map[string]any{"minPartSize": 1048576, "maxPartSize": 104857600, "maxNumSize": 1000}
				case "/object/initiate_multipart_upload":
					data = map[string]any{"upload": map[string]any{"uploadID": "ordered-log", "partSize": 1048576, "expireTime": time.Now().Add(time.Hour).UnixMilli(), "sign": map[string]any{"url": address + "/put", "parts": []any{map[string]any{"partNumber": 1}}}}}
				case "/put":
					uploaded, _ = io.ReadAll(r.Body)
					w.WriteHeader(200)
					return
				case "/object/complete_multipart_upload":
					data = map[string]any{"url": address + "/log"}
				case "/third/logs/upload":
					data = map[string]any{}
				default:
					t.Errorf("unexpected route %s", r.URL.Path)
					w.WriteHeader(404)
					return
				}
				json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data})
			}))
			defer server.Close()
			address = server.URL
			ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "log-order-test"), &ccontext.GlobalConfig{UserID: "test", IMConfig: sdk_struct.IMConfig{ApiAddr: address}})
			client := NewThird(2, "test", "flutter", dir, file.NewFile(nil, "test"))
			if err := client.uploadLogs(ctx, lines, "", orderedLogProgress{}); err != nil {
				t.Fatal(err)
			}
			archive, err := zip.NewReader(bytes.NewReader(uploaded), int64(len(uploaded)))
			if err != nil {
				t.Fatal(err)
			}
			wantCount := 1
			if lines == 0 {
				wantCount = 2
			}
			if len(archive.File) != wantCount {
				t.Fatalf("archive entries=%d", len(archive.File))
			}
			last := archive.File[len(archive.File)-1]
			r, err := last.Open()
			if err != nil {
				t.Fatal(err)
			}
			body, err := io.ReadAll(r)
			r.Close()
			if err != nil || string(body) != "latest-video-failure" {
				t.Fatalf("latest log missing: %q %v", body, err)
			}
			if lines == 0 {
				if _, err := os.Stat(filepath.Join(dir, "chat-sdk-core.2026-10-21")); err != nil {
					t.Fatal("cleanup removed current log", err)
				}
				if _, err := os.Stat(filepath.Join(dir, "open-im-sdk-core.2026-10-20")); !os.IsNotExist(err) {
					t.Fatal("cleanup kept wrong legacy log")
				}
			}
		})
	}
}
