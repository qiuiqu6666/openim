package file

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

func TestUploadDisasterSixStagesAndBucketResume(t *testing.T) {
	for _, prefer := range []bool{true, false} {
		t.Run(map[bool]string{true: "mainland", false: "other"}[prefer], func(t *testing.T) {
			events := []string{}
			completed := 0
			names := []string{}
			sign := func(hk bool) map[string]any {
				regional, accelerated := uploadRegionalHost, uploadAcceleratedHost
				if hk {
					regional, accelerated = uploadHKRegionalHost, uploadHKAcceleratedHost
				}
				parts := []any{}
				for n := 1; n <= 3; n++ {
					target, _ := json.Marshal(uploadFallbackTarget{URL: "https://" + regional + "/chat/test", Header: http.Header{"Authorization": {"signed"}}, PreferRegional: prefer, MultiBucket: true})
					parts = append(parts, map[string]any{"partNumber": n, "header": []any{map[string]any{"key": uploadFallbackHeader, "values": []string{string(target)}}}})
				}
				return map[string]any{"url": "https://" + accelerated + "/chat/test", "parts": parts}
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var data any
				var req map[string]any
				_ = json.NewDecoder(r.Body).Decode(&req)
				switch r.URL.Path {
				case "/object/part_limit":
					data = map[string]any{"minPartSize": 3, "maxPartSize": 100, "maxNumSize": 100}
				case "/object/initiate_multipart_upload":
					name := req["name"].(string)
					names = append(names, name)
					hk := strings.Contains(name, "/__cos_hk__/")
					id := "gz"
					if hk {
						id = "hk:hk"
					}
					data = map[string]any{"upload": map[string]any{"uploadID": id, "partSize": 3, "expireTime": time.Now().Add(24 * time.Hour).UnixMilli(), "sign": sign(hk)}}
				case "/object/auth_sign":
					data = sign(strings.HasPrefix(req["uploadID"].(string), "hk:"))
				case "/object/complete_multipart_upload":
					if !strings.HasPrefix(req["uploadID"].(string), "hk:") || !strings.Contains(req["name"].(string), "/__cos_hk__/") {
						t.Error("completed wrong bucket")
					}
					completed++
					data = map[string]any{"url": "hong-kong-completed"}
				default:
					t.Errorf("unexpected API %s", r.URL.Path)
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data})
			}))
			defer server.Close()
			old := http.DefaultClient
			defer func() { http.DefaultClient = old }()
			http.DefaultClient = &http.Client{Transport: fallbackTransport(func(r *http.Request) (*http.Response, error) {
				if r.Method != "PUT" && r.URL.Path != "/object/upload_relay" {
					return http.DefaultTransport.RoundTrip(r)
				}
				key := r.URL.Host
				if r.Method == "POST" {
					var target uploadFallbackTarget
					_ = json.Unmarshal([]byte(r.Header.Get(uploadFallbackHeader)), &target)
					u, _ := parseUploadURL(target.URL)
					key = "relay:" + u.Host
				}
				body, _ := io.ReadAll(r.Body)
				events = append(events, key+":"+string(body))
				status := 200
				if r.Method == "POST" {
					status = 204
				}
				if string(body) == "def" && key != "relay:"+uploadHKRegionalHost {
					status = 503
				}
				return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(""))}, nil
			})}
			path := filepath.Join(t.TempDir(), "picture.jpg")
			_ = os.WriteFile(path, []byte("abcdefghi"), 0600)
			ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "disaster"), &ccontext.GlobalConfig{UserID: "test", Token: "test", IMConfig: sdk_struct.IMConfig{ApiAddr: server.URL}})
			response, err := NewFile(&fallbackMemoryDB{}, "test").UploadFile(ctx, &UploadFileReq{Filepath: path, Name: "picture.jpg"}, nil)
			if err != nil || response.URL != "hong-kong-completed" || completed != 1 {
				t.Fatalf("upload failed %v, completed %d", err, completed)
			}
			first, second := uploadAcceleratedHost, uploadRegionalHost
			third, fourth := uploadHKAcceleratedHost, uploadHKRegionalHost
			if prefer {
				first, second = second, first
				third, fourth = fourth, third
			}
			expected := []string{first + ":abc", first + ":def", second + ":def", third + ":abc", third + ":def", fourth + ":def", "relay:" + uploadRegionalHost + ":abc", "relay:" + uploadRegionalHost + ":def", "relay:" + uploadHKRegionalHost + ":abc", "relay:" + uploadHKRegionalHost + ":def", "relay:" + uploadHKRegionalHost + ":ghi"}
			if strings.Join(events, "|") != strings.Join(expected, "|") {
				t.Fatalf("wrong order/resumed bits: %v", events)
			}
			if len(names) != 4 {
				t.Fatalf("cross-bucket sessions %v", names)
			}
		})
	}
}

func TestUploadDisasterIdleAndProgress(t *testing.T) {
	ctx, body, closeWatch, timed := uploadIdleContext(context.Background(), strings.NewReader("abc"), 40*time.Millisecond)
	defer closeWatch()
	for i := 0; i < 3; i++ {
		time.Sleep(15 * time.Millisecond)
		b := make([]byte, 1)
		body.Read(b)
		if ctx.Err() != nil {
			t.Fatal("active transfer canceled")
		}
	}
	select {
	case <-ctx.Done():
		if !timed.Load() {
			t.Fatal("idle not recorded")
		}
	case <-time.After(time.Second):
		t.Fatal("idle did not cancel")
	}
}

func TestUploadDisasterCircuitAndBudget(t *testing.T) {
	c := &uploadCircuit{}
	c.mark("gz", true)
	if !c.blocked("gz") || c.blocked("hk") {
		t.Fatal("host isolation")
	}
	c.failures["gz"] = time.Now().Add(-time.Second)
	if c.blocked("gz") {
		t.Fatal("cooldown never recovered")
	}
	p := filepath.Join(t.TempDir(), "a.jpg")
	os.WriteFile(p, []byte("image"), 0600)
	if uploadBudget(&UploadFileReq{Filepath: p}) != 30*time.Second || uploadBudget(&UploadFileReq{Filepath: "a.mp4"}) != 9*time.Minute {
		t.Fatal("wrong budget")
	}
}
