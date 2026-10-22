package chat

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/mitchellh/mapstructure"
	"github.com/openimsdk/chat/pkg/common/config"
	"github.com/openimsdk/chat/pkg/common/stickermedia"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	"google.golang.org/grpc"
	"gopkg.in/yaml.v3"
)

// Opt-in read-only check: uses deployed storage configuration and an isolated
// authorization fixture, without minting tokens or changing production data.
func TestMomentMediaProxyLiveStorage(t *testing.T) {
	path := os.Getenv("MOMENT_PROXY_LIVE_CONFIG")
	if path == "" {
		t.Skip("live storage check is opt-in")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]interface{}
	if err = yaml.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	sticker := doc["sticker"].(map[string]interface{})
	var cfg config.StickerMinio
	if err = mapstructure.Decode(sticker["minio"], &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg.CDN == "" {
		t.Fatal("test needs a configured storage CDN")
	}
	store, err := stickermedia.NewMinioStore(nil, cfg)
	if err != nil {
		t.Fatal("storage initialization failed")
	}
	gin.SetMode(gin.TestMode)
	for _, tc := range []struct {
		variant string
		size    int
		hash    string
	}{
		{size: 90935, hash: "9b118c84433635a640ebd44ab09c5e7d3bf6051b2bafa4dc3becf269becdc329"},
		{variant: "thumb", size: 21571, hash: "768413b3416d3fd82155f449a8d19540b432f1a23123011d4ed73ec3d15663c8"},
	} {
		api := &Api{chatClient: &liveMediaProxyClient{}, momentStore: store}
		r := gin.New()
		r.GET("/moments/media/:mediaId/content", api.MomentMediaContent)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest("GET", "/moments/media/image/content?variant="+tc.variant, nil))
		if w.Code != 200 || w.Header().Get("Location") != "" || w.Body.Len() != tc.size || w.Header().Get("Content-Type") != "image/jpeg" {
			t.Fatalf("status=%d size=%d type=%s redirect=%t", w.Code, w.Body.Len(), w.Header().Get("Content-Type"), w.Header().Get("Location") != "")
		}
		sum := sha256.Sum256(w.Body.Bytes())
		if tc.hash != "" && hex.EncodeToString(sum[:]) != tc.hash {
			t.Fatal("image checksum mismatch")
		}
		t.Logf("variant=%q bytes=%d checksum=%s", tc.variant, w.Body.Len(), hex.EncodeToString(sum[:]))
	}
}

type liveMediaProxyClient struct{ pb.ChatClient }

func (*liveMediaProxyClient) AuthorizeMomentMedia(_ context.Context, req *pb.AuthorizeMomentMediaReq, _ ...grpc.CallOption) (*pb.AuthorizeMomentMediaResp, error) {
	variant := "original"
	if req.Variant == "thumb" {
		variant = "thumb"
	}
	return &pb.AuthorizeMomentMediaResp{ObjectKey: "moment/im_4b8e128f8a68dddd634329df20861f45/legacy_moment_media_ca1db8ccf1fc5117b74d90f7433dcdb0/" + variant, ContentType: "image/jpeg"}, nil
}
