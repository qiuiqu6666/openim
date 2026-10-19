package third

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/internal/third/file"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/tools/errs"
)

func TestLogTailSelection(t *testing.T) {
	for _, test := range []struct {
		content string
		n       int
		want    []string
	}{
		{"a\nb\nc\n", 2, []string{"b", "c"}},
		{"a\r\nb\r\nc", 2, []string{"b", "c"}},
		{"a\n\nb\n", 2, []string{"", "b"}},
		{"one", 10000, []string{"one"}},
		{"", 10000, nil},
	} {
		path := filepath.Join(t.TempDir(), "log")
		if err := os.WriteFile(path, []byte(test.content), 0600); err != nil {
			t.Fatal(err)
		}
		got, err := readLastNLines(path, test.n)
		if err != nil || !reflect.DeepEqual(got, test.want) {
			t.Fatalf("%q: got %q, err %v", test.content, got, err)
		}
		if _, err := readLastNLines(path, 0); err == nil {
			t.Fatal("zero line count must be rejected")
		}
	}
}

func TestLogTailOversizedLine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "log")
	content := strings.Repeat("x", 11*1024*1024) + "\nlatest-error\n"
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := readLastNLines(path, 10000)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(strings.Join(got, "\n"), "latest-error") || len(strings.Join(got, "\n")) > maxLogTailBytes+128 {
		t.Fatal("tail missing or unbounded")
	}
	if err := os.WriteFile(path, []byte(strings.Repeat("z", 11*1024*1024)), 0600); err != nil {
		t.Fatal(err)
	}
	got, err = readLastNLines(path, 10000)
	if err != nil || len(strings.Join(got, "\n")) > maxLogTailBytes+128 {
		t.Fatalf("single oversized line: %v", err)
	}
}

var errZipFooter = errors.New("simulated disk full writing ZIP footer")

type failZipFooter struct{ bytes.Buffer }

func (w *failZipFooter) Write(p []byte) (int, error) {
	if bytes.Contains(p, []byte{'P', 'K', 5, 6}) {
		return 0, errZipFooter
	}
	return w.Buffer.Write(p)
}

func TestLogArchiveFinalization(t *testing.T) {
	path := filepath.Join(t.TempDir(), "log")
	if err := os.WriteFile(path, []byte("diagnostic text"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := writeLogArchive(&failZipFooter{}, []string{path}); !errors.Is(err, errZipFooter) {
		t.Fatalf("lost close error: %v", err)
	}
	var output bytes.Buffer
	if err := writeLogArchive(&output, []string{path}); err != nil {
		t.Fatal(err)
	}
	archive, err := zip.NewReader(bytes.NewReader(output.Bytes()), int64(output.Len()))
	if err != nil {
		t.Fatal(err)
	}
	r, err := archive.File[0].Open()
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	data, err := io.ReadAll(r)
	if err != nil || string(data) != "diagnostic text" {
		t.Fatalf("archive contents: %q, %v", data, err)
	}
}

type logTestProgress struct{}

func (logTestProgress) OnProgress(int64, int64) {}

func TestLogUploadFailureStages(t *testing.T) {
	for _, failure := range []string{"transfer", "register", "none"} {
		t.Run(failure, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, "open-im-sdk-core.2026-10-19"), []byte("recent diagnostic\n"), 0600); err != nil {
				t.Fatal(err)
			}
			var address string
			puts, registrations := 0, 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var data any
				switch r.URL.Path {
				case "/object/part_limit":
					data = map[string]any{"minPartSize": 1048576, "maxPartSize": 104857600, "maxNumSize": 1000}
				case "/object/initiate_multipart_upload":
					data = map[string]any{"upload": map[string]any{"uploadID": "log-upload", "partSize": 1048576, "expireTime": time.Now().Add(time.Hour * 24).UnixMilli(), "sign": map[string]any{"url": address + "/put", "parts": []any{map[string]any{"partNumber": 1}}}}}
				case "/put":
					puts++
					_, _ = io.Copy(io.Discard, r.Body)
					if failure == "transfer" {
						w.WriteHeader(403)
					} else {
						w.WriteHeader(200)
					}
					return
				case "/object/complete_multipart_upload":
					data = map[string]any{"url": address + "/uploaded-log"}
				case "/third/logs/upload":
					registrations++
					if failure == "register" {
						json.NewEncoder(w).Encode(map[string]any{"errCode": 1002, "errMsg": "denied"})
						return
					}
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
			ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "log-stage-test"), &ccontext.GlobalConfig{UserID: "test", IMConfig: sdk_struct.IMConfig{ApiAddr: address}})
			client := NewThird(2, "test", "flutter", dir, file.NewFile(nil, "test"))
			err := client.uploadLogs(ctx, 10000, `{"biz":"feedback"}`, logTestProgress{})
			if failure == "none" {
				if err != nil {
					t.Fatal(err)
				}
			} else if err == nil || !strings.Contains(err.Error(), "sdk_log_stage="+failure) {
				t.Fatalf("expected %s failure, got %v", failure, err)
			}
			if puts != 1 || (failure == "transfer" && registrations != 0) || (failure != "transfer" && registrations != 1) {
				t.Fatalf("puts %d, registrations %d", puts, registrations)
			}
			if failure == "register" {
				var coded errs.CodeError
				if !errors.As(err, &coded) || coded.Code() != 1002 {
					t.Fatal("lost server error code")
				}
			}
			entries, _ := os.ReadDir(dir)
			if len(entries) != 1 {
				t.Fatalf("temporary files leaked: %v", entries)
			}
		})
	}
	client := NewThird(2, "test", "flutter", t.TempDir(), nil)
	err := client.uploadLogs(context.Background(), 10000, "", nil)
	if err == nil || !strings.Contains(err.Error(), "sdk_log_stage=collect") {
		t.Fatalf("missing log: %v", err)
	}
	client.logUploadLock.Lock()
	defer client.logUploadLock.Unlock()
	err = client.uploadLogs(context.Background(), 10000, "", nil)
	if err == nil || !strings.Contains(err.Error(), "sdk_log_stage=prepare") {
		t.Fatalf("busy: %v", err)
	}
}

func TestLogStagePreservesSDKNetworkCode(t *testing.T) {
	err := logUploadStageError("transfer", sdkerrs.ErrNetwork.WrapMsg("connection lost"))
	var coded errs.CodeError
	if !errors.As(err, &coded) || coded.Code() != sdkerrs.NetworkError {
		t.Fatalf("lost network code: %v", err)
	}
}
