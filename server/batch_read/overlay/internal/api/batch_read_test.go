package api

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/openimsdk/open-im-server/v3/internal/api/batchread"
	"github.com/openimsdk/protocol/constant"
	"github.com/openimsdk/protocol/msg"
	"google.golang.org/grpc"
)

type batchReadClient struct {
	msg.MsgClient
	user string
}

func (f *batchReadClient) GetConversationsHasReadAndMaxSeq(_ context.Context, r *msg.GetConversationsHasReadAndMaxSeqReq, _ ...grpc.CallOption) (*msg.GetConversationsHasReadAndMaxSeqResp, error) {
	f.user = r.UserID
	return &msg.GetConversationsHasReadAndMaxSeqResp{Seqs: map[string]*msg.Seqs{"sg_owned": {MaxSeq: 5}}}, nil
}
func TestBatchReadHandlerUsesAuthenticatedSubject(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, user := range []string{"alice", ""} {
		client := &batchReadClient{}
		r := gin.New()
		r.Use(func(c *gin.Context) {
			if user != "" {
				c.Set(constant.OpUserID, user)
			}
		})
		r.POST("/prepare", batchReadHandler(batchread.New(client), true))
		req := httptest.NewRequest("POST", "/prepare", strings.NewReader(`{"scope":"group","userID":"victim"}`))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		var body struct {
			ErrCode int `json:"errCode"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if user != "" && (client.user != "alice" || body.ErrCode != 0) {
			t.Fatalf("wrong subject %s: %s", client.user, w.Body)
		}
		if user == "" && (client.user != "" || body.ErrCode == 0) {
			t.Fatalf("anonymous accepted: %s", w.Body)
		}
	}
}
