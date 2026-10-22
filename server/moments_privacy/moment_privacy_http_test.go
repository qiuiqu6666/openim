package chat

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/proto"
	"net/http/httptest"
	"testing"
)

type privacyHTTPClient struct {
	pb.ChatClient
	response *pb.MomentSettingsResp
}

func (s *privacyHTTPClient) GetMomentSettings(context.Context, *pb.GetMomentSettingsReq, ...grpc.CallOption) (*pb.MomentSettingsResp, error) {
	raw, err := proto.Marshal(s.response)
	if err != nil {
		return nil, err
	}
	var copied pb.MomentSettingsResp
	err = proto.Unmarshal(raw, &copied)
	return &copied, err
}
func TestMomentSettingsPrivacyHTTPContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, populated := range []bool{false, true} {
		response := &pb.MomentSettingsResp{PrivacyListsLoaded: true, UpdatedAt: 1700000000123, Version: 8}
		if populated {
			response.BlockedViewerIDs = []string{"blocked"}
			response.HiddenAuthorIDs = []string{"hidden"}
		}
		api := &Api{chatClient: &privacyHTTPClient{response: response}}
		r := gin.New()
		r.GET("/moments/settings", api.GetMomentSettings)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest("GET", "/moments/settings", nil))
		var got struct {
			ErrCode int `json:"errCode"`
			Data    struct {
				Blocked   []string `json:"blockedViewerIDs"`
				Hidden    []string `json:"hiddenAuthorIDs"`
				Loaded    bool     `json:"privacyListsLoaded"`
				UpdatedAt int64    `json:"updatedAt"`
				Version   int64    `json:"version"`
			} `json:"data"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if got.ErrCode != 0 || !got.Data.Loaded || got.Data.UpdatedAt != response.UpdatedAt || got.Data.Version != 8 {
			t.Fatal(w.Body.String())
		}
		want := 0
		if populated {
			want = 1
		}
		if len(got.Data.Blocked) != want || len(got.Data.Hidden) != want {
			t.Fatal(w.Body.String())
		}
	}
}
