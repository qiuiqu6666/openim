package uploadregion

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/openimsdk/protocol/third"
)

func TestMainlandClassification(t *testing.T) {
	for _, tc := range []struct {
		region string
		want   bool
	}{
		{"中国|广东省|深圳市|电信|CN", true}, {"China|Guangdong|Shenzhen|ISP|CN", true},
		{"中国|香港特别行政区|0|0|CN", false}, {"中国|澳门|0|0|CN", false}, {"中国|台湾省|0|0|CN", false},
		{"Hong Kong|0|0|0|HK", false}, {"美国|加利福尼亚|0|0|US", false}, {"", false}, {"0|0|0|0|0", false},
	} {
		if got := mainland(tc.region); got != tc.want {
			t.Errorf("%q: %v", tc.region, got)
		}
	}
}

func TestOnlyLocalProxyCanProvideClientIP(t *testing.T) {
	for _, tc := range []struct{ peer, header, want string }{
		{"8.8.8.8:1234", "223.5.5.5", "8.8.8.8"}, {"127.0.0.1:1234", "223.5.5.5", "223.5.5.5"},
		{"[::1]:1234", "223.5.5.5", "223.5.5.5"}, {"127.0.0.1:1234", "invalid", "127.0.0.1"},
	} {
		r := httptest.NewRequest("POST", "/", nil)
		r.RemoteAddr = tc.peer
		r.Header.Set("X-Real-IP", tc.header)
		if got := clientIP(r).String(); got != tc.want {
			t.Errorf("peer=%s got %s", tc.peer, got)
		}
	}
}

func TestAnnotatePreservesSignedTarget(t *testing.T) {
	value := `{"url":"https://origin.example/path?q-signature=signed","header":{"Authorization":["signed-header"]}}`
	for _, preference := range []bool{true, false} {
		h := []*third.KeyValues{{Key: fallbackHeader, Values: []string{value}}}
		Annotate(nil, []*third.SignPart{{Header: h}}, preference)
		var got struct {
			URL            string              `json:"url"`
			Header         map[string][]string `json:"header"`
			PreferRegional bool                `json:"preferRegional"`
		}
		if json.Unmarshal([]byte(h[0].Values[0]), &got) != nil || got.PreferRegional != preference || got.URL != "https://origin.example/path?q-signature=signed" || got.Header["Authorization"][0] != "signed-header" {
			t.Fatal("annotation changed signed data")
		}
	}
}

func TestLiveGeoDatabase(t *testing.T) {
	if os.Getenv("UPLOAD_REGION_LIVE_DB") == "" {
		t.Skip("explicit local database check")
	}
	for _, tc := range []struct {
		ip   string
		want bool
	}{{"223.5.5.5", true}, {"8.8.8.8", false}, {"168.95.1.1", false}, {"1.36.1.1", false}, {"202.175.1.1", false}, {"2400:3200::1", true}, {"2001:4860:4860::8888", false}} {
		r := httptest.NewRequest("POST", "/", nil)
		r.RemoteAddr = "127.0.0.1:1234"
		r.Header.Set("X-Real-IP", tc.ip)
		if got := PreferRegional(r); got != tc.want {
			t.Errorf("IP %s mainland=%v want=%v", tc.ip, got, tc.want)
		}
	}
}
