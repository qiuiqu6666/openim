package objectstorage

import (
	"context"
	"encoding/json"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/openimsdk/tools/s3/cos"
)

func TestCOSFallbackSignsEachEndpoint(t *testing.T) {
	c, err := NewCOS(cos.Config{BucketURL: acceleratedOrigin, SecretID: "test", SecretKey: "test", PublicRead: true}, "")
	if err != nil {
		t.Fatal(err)
	}
	single, err := c.PresignedPutObject(context.Background(), "chat/temp/test", time.Minute, nil)
	if err != nil {
		t.Fatal(err)
	}
	var target fallbackTarget
	if err := json.Unmarshal([]byte(single.Header.Get(fallbackHeader)), &target); err != nil {
		t.Fatal(err)
	}
	primary, _ := url.Parse(single.URL)
	backup, _ := url.Parse(target.URL)
	if primary.Host == backup.Host || backup.Host != "gz99chat-1416337673.cos.ap-guangzhou.myqcloud.com" || primary.Query().Get("q-signature") == backup.Query().Get("q-signature") {
		t.Fatal("regional URL must be independently signed")
	}
	parts, err := c.AuthSign(context.Background(), "upload-id", "chat/data/hash/test", time.Minute, []int{1, 2})
	if err != nil {
		t.Fatal(err)
	}
	for _, part := range parts.Parts {
		if err := json.Unmarshal([]byte(part.Header.Get(fallbackHeader)), &target); err != nil {
			t.Fatal(err)
		}
		u, _ := url.Parse(target.URL)
		if u.Query().Get("uploadId") != "upload-id" || u.Query().Get("partNumber") == "" || !strings.Contains(target.Header.Get("Authorization"), "q-signature=") || target.Header.Get("Authorization") == parts.Header.Get("Authorization") {
			t.Fatal("invalid regional part signature")
		}
	}
}
