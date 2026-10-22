package uploadrelay

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/openimsdk/protocol/constant"
)

type transport func(*http.Request) (*http.Response, error)

func (fn transport) RoundTrip(r *http.Request) (*http.Response, error) { return fn(r) }
func metadata(host string) string {
	b, _ := json.Marshal(Target{URL: "https://" + host + "/chat/temp/test?partNumber=1&uploadId=id", Header: http.Header{"Authorization": {"q-signature=test"}, "Host": {host}}})
	return string(b)
}
func TestRelayStreamsSignedPartAndDoesNotForwardIMToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	calls := 0
	h := New(&http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		calls++
		b, _ := io.ReadAll(r.Body)
		if string(b) != "payload" || r.URL.Host != RegionalHost || r.Method != "PUT" || r.Header.Get("token") != "" || r.Header.Get("Authorization") == "" || r.ContentLength != 7 {
			t.Fatal("bad storage request")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(""))}, nil
	})})
	for _, test := range []struct {
		name, user, target string
		size               int64
		want               int
	}{
		{"ok", "user", metadata(RegionalHost), 7, 204},
		{"no session", "", metadata(RegionalHost), 7, 401},
		{"foreign host", "user", metadata("attacker.example"), 7, 400},
		{"oversize", "user", metadata(RegionalHost), MaxPartBytes + 1, 413},
		{"unknown size", "user", metadata(RegionalHost), -1, 413},
		{"unsigned", "user", `{"url":"https://` + RegionalHost + `/chat/temp/test"}`, 7, 400},
	} {
		t.Run(test.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Set(constant.OpUserID, test.user)
			c.Request = httptest.NewRequest("POST", "/object/upload_relay", strings.NewReader("payload"))
			c.Request.ContentLength = test.size
			c.Request.Header.Set(TargetHeader, test.target)
			c.Request.Header.Set("token", "private-token")
			h(c)
			c.Writer.WriteHeaderNow()
			if w.Code != test.want {
				t.Fatalf("status %d want %d", w.Code, test.want)
			}
		})
	}
	if calls != 1 {
		t.Fatalf("unexpected outbound calls: %d", calls)
	}
}
func TestRelayDoesNotFollowRedirect(t *testing.T) {
	client := &http.Client{Transport: transport(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 302, Header: http.Header{"Location": {"http://127.0.0.1/private"}}, Body: io.NopCloser(strings.NewReader("sensitive"))}, nil
	})}
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Set(constant.OpUserID, "user")
	c.Request = httptest.NewRequest("POST", "/object/upload_relay", strings.NewReader("x"))
	c.Request.Header.Set(TargetHeader, metadata(RegionalHost))
	New(client)(c)
	c.Writer.WriteHeaderNow()
	if w.Code != 502 || w.Body.Len() != 0 || w.Header().Get("Location") != "" {
		t.Fatal("unsafe redirect response")
	}
}
