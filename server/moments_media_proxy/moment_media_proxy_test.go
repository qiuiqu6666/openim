package chat

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/openimsdk/chat/pkg/common/config"
	"github.com/openimsdk/chat/pkg/common/stickermedia"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	"github.com/openimsdk/tools/errs"
	"google.golang.org/grpc"
)

type mediaProxyClient struct {
	pb.ChatClient
	deny    bool
	variant string
}

func (s *mediaProxyClient) AuthorizeMomentMedia(_ context.Context, req *pb.AuthorizeMomentMediaReq, _ ...grpc.CallOption) (*pb.AuthorizeMomentMediaResp, error) {
	s.variant = req.Variant
	if s.deny {
		return nil, errs.ErrNoPermission
	}
	key := "moment/original"
	if req.Variant == "thumb" {
		key = "moment/thumb"
	}
	return &pb.AuthorizeMomentMediaResp{ObjectKey: key, ContentType: "image/jpeg"}, nil
}

func TestMomentMediaProxyStableURL(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, tc := range []struct {
		name, query, byteRange string
		deny, missing          bool
		wantCode               int
		wantBody               string
	}{
		{name: "original", wantCode: 200, wantBody: "original-image"},
		{name: "thumbnail", query: "?variant=thumb", wantCode: 200, wantBody: "thumb-image"},
		{name: "range", byteRange: "bytes=0-3", wantCode: 206, wantBody: "orig"},
		{name: "denied", deny: true},
		{name: "missing", missing: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			storageCalls := 0
			storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				storageCalls++
				if tc.deny {
					t.Error("storage accessed before authorization")
				}
				if tc.missing {
					w.WriteHeader(404)
					return
				}
				body := "original-image"
				if strings.HasSuffix(r.URL.Path, "/thumb") {
					body = "thumb-image"
				}
				w.Header().Set("Last-Modified", "Wed, 21 Oct 2026 00:00:00 GMT")
				w.Header().Set("ETag", `"test-etag"`)
				w.Header().Set("Content-Type", "image/jpeg")
				code := 200
				if r.Method == "GET" && r.Header.Get("Range") != "" {
					var start, end int
					if _, err := fmt.Sscanf(r.Header.Get("Range"), "bytes=%d-%d", &start, &end); err != nil {
						t.Error(err)
					}
					w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, len(body)))
					body = body[start : end+1]
					code = 206
				}
				w.Header().Set("Content-Length", fmt.Sprint(len(body)))
				w.WriteHeader(code)
				if r.Method != "HEAD" {
					_, _ = w.Write([]byte(body))
				}
			}))
			defer storage.Close()
			store, err := stickermedia.NewMinioStore(nil, config.StickerMinio{Bucket: "media", InternalAddress: storage.URL, AccessKeyID: "test-access", SecretAccessKey: "test-secret", Region: "us-east-1"})
			if err != nil {
				t.Fatal(err)
			}
			client := &mediaProxyClient{deny: tc.deny}
			api := &Api{chatClient: client, momentStore: store}
			router := gin.New()
			router.GET("/moments/media/:mediaId/content", api.MomentMediaContent)
			req := httptest.NewRequest("GET", "/moments/media/image/content"+tc.query, nil)
			req.Header.Set("Range", tc.byteRange)
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)
			if w.Header().Get("Location") != "" {
				t.Fatal("media must never redirect to a storage hostname")
			}
			if tc.deny || tc.missing {
				if strings.Contains(w.Body.String(), "image") && w.Header().Get("Content-Type") == "image/jpeg" {
					t.Fatal("private image leaked")
				}
				if !strings.Contains(w.Body.String(), "errCode") {
					t.Fatal(w.Body.String())
				}
				if tc.deny && storageCalls != 0 {
					t.Fatal("authorization must precede storage reads")
				}
				return
			}
			if w.Code != tc.wantCode || w.Body.String() != tc.wantBody {
				t.Fatalf("status=%d body=%q", w.Code, w.Body.String())
			}
			if w.Header().Get("Cache-Control") != "private, no-store" || w.Header().Get("Content-Type") != "image/jpeg" {
				t.Fatal(w.Header())
			}
			if tc.query != "" && client.variant != "thumb" {
				t.Fatal("thumbnail variant not authorized")
			}
			if tc.byteRange != "" && w.Header().Get("Content-Range") != "bytes 0-3/14" {
				t.Fatal(w.Header())
			}
		})
	}
}
