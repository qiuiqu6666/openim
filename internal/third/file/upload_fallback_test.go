package file

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

type fallbackTransport func(*http.Request) (*http.Response, error)

type fallbackMemoryDB struct {
	db_interface.DataBase
	row *model_struct.LocalUpload
}

func (d *fallbackMemoryDB) GetUpload(context.Context, string) (*model_struct.LocalUpload, error) {
	if d.row == nil {
		return nil, errors.New("not found")
	}
	copy := *d.row
	return &copy, nil
}
func (d *fallbackMemoryDB) InsertUpload(_ context.Context, row *model_struct.LocalUpload) error {
	copy := *row
	d.row = &copy
	return nil
}
func (d *fallbackMemoryDB) UpdateUpload(ctx context.Context, row *model_struct.LocalUpload) error {
	return d.InsertUpload(ctx, row)
}
func (d *fallbackMemoryDB) DeleteUpload(context.Context, string) error { d.row = nil; return nil }

func (fn fallbackTransport) RoundTrip(r *http.Request) (*http.Response, error) { return fn(r) }

func fallbackContext() context.Context {
	ctx := ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{Token: "im-session", IMConfig: sdk_struct.IMConfig{ApiAddr: "https://im.example"}})
	return context.WithValue(ctx, uploadRouteKey{}, &uploadRouteState{})
}
func fallbackSign() (*url.URL, http.Header) {
	u, _ := url.Parse("https://" + uploadAcceleratedHost + "/chat/temp/test?partNumber=2&uploadId=test")
	data, _ := json.Marshal(uploadFallbackTarget{URL: "https://" + uploadRegionalHost + "/chat/temp/test?partNumber=2&uploadId=test", Header: http.Header{"Authorization": {"regional-signature"}}})
	h := http.Header{"Authorization": {"accelerated-signature"}}
	h.Set(uploadFallbackHeader, string(data))
	return u, h
}

func TestUploadFallbackRoutesAndReplay(t *testing.T) {
	ctx := fallbackContext()
	u, h := fallbackSign()
	calls := 0
	client := &http.Client{Transport: fallbackTransport(func(r *http.Request) (*http.Response, error) {
		calls++
		body, _ := io.ReadAll(r.Body)
		if string(body) != "complete-part" {
			t.Fatalf("replayed body %q", body)
		}
		switch calls {
		case 1, 2:
			host, auth := uploadAcceleratedHost, "accelerated-signature"
			if calls == 2 {
				host, auth = uploadRegionalHost, "regional-signature"
			}
			if r.URL.Host != host || r.Header.Get("Authorization") != auth || r.Header.Get(uploadFallbackHeader) != "" || r.Header.Get("token") != "" || r.Method != "PUT" {
				t.Fatalf("incorrect direct request")
			}
			return nil, &net.DNSError{Err: "no such host", Name: host}
		default:
			if r.URL.String() != "https://im.example/object/upload_relay" || r.Method != "POST" || r.Header.Get("token") != "im-session" || r.Header.Get("Authorization") != "" || r.Header.Get(uploadFallbackHeader) == "" {
				t.Fatal("incorrect relay request")
			}
			return &http.Response{StatusCode: 204, Body: io.NopCloser(strings.NewReader("")), Header: make(http.Header)}, nil
		}
	})}
	for i := 0; i < 3; i++ {
		err := (&File{}).doPut(ctx, client, u, h, strings.NewReader("complete-part"), 13)
		if (i < 2) != (err != nil) {
			t.Fatalf("attempt %d: %v", i, err)
		}
	}
	if h.Get(uploadFallbackHeader) == "" {
		t.Fatal("mutated cached signature")
	}
}

func TestUploadFallbackStopsOnAuthorizationAndCancellation(t *testing.T) {
	for _, failure := range []error{&uploadHTTPError{status: 403}, context.Canceled, context.DeadlineExceeded} {
		ctx := fallbackContext()
		state := ctx.Value(uploadRouteKey{}).(*uploadRouteState)
		state.available = true
		if !errors.Is(advanceUploadRoute(ctx, failure), failure) || state.tier != 0 {
			t.Fatal("retried terminal error")
		}
	}
}

func TestUploadFallbackRejectsTamperingAndRelayEnvelope(t *testing.T) {
	u, h := fallbackSign()
	ctx := fallbackContext()
	h.Set(uploadFallbackHeader, strings.ReplaceAll(h.Get(uploadFallbackHeader), uploadRegionalHost, "attacker.example"))
	if _, _, err := selectUploadRoute(ctx, u, h); err == nil {
		t.Fatal("accepted arbitrary fallback host")
	}
	u, h = fallbackSign()
	ctx.Value(uploadRouteKey{}).(*uploadRouteState).tier = 2
	client := &http.Client{Transport: fallbackTransport(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"errCode":1501}`))}, nil
	})}
	if err := (&File{}).doPut(ctx, client, u, h, strings.NewReader("x"), 1); err == nil {
		t.Fatal("committed unauthenticated relay response")
	}
}

func TestUploadFallbackMultipartKeepsCommittedParts(t *testing.T) {
	puts := map[string]int{}
	completed, initiated := 0, 0
	sign := func() map[string]any {
		parts := []any{}
		for _, n := range []string{"1", "2", "3"} {
			meta, _ := json.Marshal(uploadFallbackTarget{URL: "https://" + uploadRegionalHost + "/chat/temp/test?partNumber=" + n, Header: http.Header{"Authorization": {"regional-signature"}}})
			parts = append(parts, map[string]any{"partNumber": int(n[0] - '0'), "query": []any{map[string]any{"key": "partNumber", "values": []string{n}}}, "header": []any{map[string]any{"key": uploadFallbackHeader, "values": []string{string(meta)}}}})
		}
		return map[string]any{"url": "https://" + uploadAcceleratedHost + "/chat/temp/test", "parts": parts}
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var data any
		switch r.URL.Path {
		case "/object/part_limit":
			data = map[string]any{"minPartSize": 3, "maxPartSize": 100, "maxNumSize": 100}
		case "/object/initiate_multipart_upload":
			initiated++
			data = map[string]any{"upload": map[string]any{"uploadID": "fallback-id", "partSize": 3, "expireTime": time.Now().Add(24 * time.Hour).UnixMilli(), "sign": sign()}}
		case "/object/auth_sign":
			data = sign()
		case "/object/complete_multipart_upload":
			completed++
			data = map[string]any{"url": "completed"}
		case "/object/upload_relay":
			body, _ := io.ReadAll(r.Body)
			if string(body) != "ghi" {
				t.Errorf("relay body %q", body)
			}
			puts["relay3"]++
			w.WriteHeader(204)
			return
		default:
			t.Errorf("unexpected route %s", r.URL.Path)
			w.WriteHeader(404)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data})
	}))
	defer server.Close()
	previous := http.DefaultClient
	http.DefaultClient = &http.Client{Transport: fallbackTransport(func(r *http.Request) (*http.Response, error) {
		if r.URL.Host != uploadAcceleratedHost && r.URL.Host != uploadRegionalHost {
			return http.DefaultTransport.RoundTrip(r)
		}
		n := r.URL.Query().Get("partNumber")
		tier := "primary"
		if r.URL.Host == uploadRegionalHost {
			tier = "regional"
		}
		puts[tier+n]++
		body, _ := io.ReadAll(r.Body)
		expected := map[string]string{"1": "abc", "2": "def", "3": "ghi"}[n]
		if string(body) != expected {
			t.Errorf("%s%s body %q", tier, n, body)
		}
		status := 200
		if (tier == "primary" && n == "2") || (tier == "regional" && n == "3") {
			status = 503
		}
		return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(""))}, nil
	})}
	defer func() { http.DefaultClient = previous }()
	path := filepath.Join(t.TempDir(), "parts.bin")
	if err := os.WriteFile(path, []byte("abcdefghi"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "fallback-resume"), &ccontext.GlobalConfig{UserID: "test", Token: "test", IMConfig: sdk_struct.IMConfig{ApiAddr: server.URL}})
	db := &fallbackMemoryDB{}
	result, err := NewFile(db, "test").UploadFile(ctx, &UploadFileReq{Filepath: path, Name: "parts.bin"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.URL != "completed" || completed != 1 || initiated != 1 || db.row != nil || len(puts) != 5 {
		t.Fatalf("result=%v complete=%d initiate=%d puts=%v", result, completed, initiated, puts)
	}
	for _, key := range []string{"primary1", "primary2", "regional2", "regional3", "relay3"} {
		if puts[key] != 1 {
			t.Fatalf("reuploaded committed part: %v", puts)
		}
	}
}
