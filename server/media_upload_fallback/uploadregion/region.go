// Package uploadregion annotates upload signatures using the connection's IP,
// without sending addresses to an external service or changing signed URLs.
package uploadregion

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"

	"github.com/lionsoul2014/ip2region/binding/golang/xdb"
	"github.com/openimsdk/protocol/third"
)

const fallbackHeader = "X-Openim-Upload-Fallback"

var geo struct {
	once   sync.Once
	mu     sync.Mutex
	v4, v6 *xdb.Searcher
}

// The existing local nginx sanitizes X-Real-IP using PROXY protocol. Public
// direct connections cannot override their peer IP with caller-supplied headers.
func clientIP(r *http.Request) net.IP {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	if ip != nil && ip.IsLoopback() {
		if forwarded := net.ParseIP(strings.TrimSpace(r.Header.Get("X-Real-IP"))); forwarded != nil {
			return forwarded
		}
	}
	return ip
}

func mainland(region string) bool {
	parts := strings.Split(region, "|")
	if len(parts) != 5 {
		return false
	}
	for _, part := range parts {
		p := strings.ToUpper(strings.TrimSpace(part))
		if p == "HK" || p == "MO" || p == "TW" || strings.Contains(p, "香港") || strings.Contains(p, "澳门") || strings.Contains(p, "台湾") || strings.Contains(p, "HONG KONG") || strings.Contains(p, "MACAO") || strings.Contains(p, "MACAU") || strings.Contains(p, "TAIWAN") {
			return false
		}
	}
	return parts[0] == "中国" || strings.EqualFold(parts[4], "CN")
}

func PreferRegional(r *http.Request) bool {
	ip := clientIP(r)
	if ip == nil || ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() || ip.IsLinkLocalUnicast() {
		return false
	}
	geo.once.Do(func() {
		v4 := os.Getenv("OPENIM_UPLOAD_GEOIP_V4")
		if v4 == "" {
			v4 = "/srv/99chat-production/app/config/chat/ip2region_v4.xdb"
		}
		v6 := os.Getenv("OPENIM_UPLOAD_GEOIP_V6")
		if v6 == "" {
			v6 = "/srv/99chat-production/app/config/chat/ip2region_v6.xdb"
		}
		geo.v4, _ = xdb.NewWithFileOnly(xdb.IPv4, v4)
		geo.v6, _ = xdb.NewWithFileOnly(xdb.IPv6, v6)
	})
	searcher := geo.v4
	if ip.To4() == nil {
		searcher = geo.v6
	}
	if searcher == nil {
		return false
	}
	geo.mu.Lock()
	region, err := searcher.Search(ip.String())
	geo.mu.Unlock()
	return err == nil && mainland(region)
}

func Annotate(headers []*third.KeyValues, parts []*third.SignPart, preferRegional bool) {
	annotateHeaders(headers, preferRegional)
	for _, part := range parts {
		if part != nil {
			annotateHeaders(part.Header, preferRegional)
		}
	}
}

func annotateHeaders(headers []*third.KeyValues, preferRegional bool) {
	for _, h := range headers {
		if h == nil || !strings.EqualFold(h.Key, fallbackHeader) {
			continue
		}
		for i, value := range h.Values {
			var target map[string]json.RawMessage
			if len(value) > 16*1024 || json.Unmarshal([]byte(value), &target) != nil || target == nil {
				continue
			}
			flag := "false"
			if preferRegional {
				flag = "true"
			}
			target["preferRegional"] = json.RawMessage(flag)
			target["multiBucket"] = json.RawMessage("true")
			if data, err := json.Marshal(target); err == nil {
				h.Values[i] = string(data)
			}
		}
	}
}
