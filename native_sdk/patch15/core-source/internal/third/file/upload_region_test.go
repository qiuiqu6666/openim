package file

import (
	"encoding/json"
	"net"
	"testing"
)

func TestUploadRegionPreferenceAndFallbackOrder(t *testing.T) {
	for _, mainland := range []bool{true, false} {
		ctx := fallbackContext()
		original, headers := fallbackSign()
		var metadata uploadFallbackTarget
		if err := json.Unmarshal([]byte(headers.Get(uploadFallbackHeader)), &metadata); err != nil {
			t.Fatal(err)
		}
		metadata.PreferRegional = mainland
		encoded, _ := json.Marshal(metadata)
		headers.Set(uploadFallbackHeader, string(encoded))
		first, second := uploadAcceleratedHost, uploadRegionalHost
		firstAuth, secondAuth := "accelerated-signature", "regional-signature"
		if mainland {
			first, second = second, first
			firstAuth, secondAuth = secondAuth, firstAuth
		}
		u, h, err := selectUploadRoute(ctx, original, headers)
		if err != nil || u.Host != first || h.Get("Authorization") != firstAuth {
			t.Fatalf("mainland=%v first target incorrect", mainland)
		}
		advanceUploadRoute(ctx, &net.DNSError{Err: "no such host"})
		// A signature refresh/network change must not reset the in-flight order.
		metadata.PreferRegional = !mainland
		encoded, _ = json.Marshal(metadata)
		headers.Set(uploadFallbackHeader, string(encoded))
		u, h, err = selectUploadRoute(ctx, original, headers)
		if err != nil || u.Host != second || h.Get("Authorization") != secondAuth {
			t.Fatalf("mainland=%v second target incorrect", mainland)
		}
		advanceUploadRoute(ctx, &net.DNSError{Err: "no such host"})
		u, h, err = selectUploadRoute(ctx, original, headers)
		if err != nil || u.Host != "im.example" || h.Get("token") != "im-session" {
			t.Fatalf("mainland=%v relay incorrect", mainland)
		}
		if json.Unmarshal([]byte(h.Get(uploadFallbackHeader)), &metadata) != nil || metadata.URL[:8] != "https://" {
			t.Fatal("missing signed regional relay target")
		}
	}
}
