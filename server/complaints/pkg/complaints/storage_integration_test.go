package complaints

import (
	"bytes"
	"context"
	"github.com/google/uuid"
	"github.com/mitchellh/mapstructure"
	"github.com/openimsdk/chat/pkg/common/adminauth"
	"github.com/openimsdk/chat/pkg/common/config"
	"github.com/openimsdk/chat/pkg/common/stickermedia"
	"gopkg.in/yaml.v3"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestComplaintPermissionIsolation(t *testing.T) {
	if !adminauth.ValidPermission("complaints") {
		t.Fatal("complaint permission missing")
	}
	for _, path := range []string{"/complaints/search", "/complaints/detail", "/complaints/screenshot", "/complaints/update"} {
		if !adminauth.Allowed(&adminauth.Principal{Permissions: []string{"complaints"}}, path, "POST", nil) {
			t.Fatal("complaint grant denied", path)
		}
		if adminauth.Allowed(&adminauth.Principal{Permissions: []string{"feedback"}}, path, "POST", nil) {
			t.Fatal("unrelated grant accepted", path)
		}
	}
}
func TestRealScreenshotStorageRoundTrip(t *testing.T) {
	dir := os.Getenv("COMPLAINT_TEST_CONFIG")
	if dir == "" {
		t.Skip("set COMPLAINT_TEST_CONFIG for object storage verification")
	}
	raw, err := os.ReadFile(filepath.Join(dir, "chat-rpc-chat.yml"))
	if err != nil {
		t.Fatal("test config unavailable")
	}
	var data map[string]any
	if err = yaml.Unmarshal(raw, &data); err != nil {
		t.Fatal(err)
	}
	var cfg config.Chat
	if err = mapstructure.Decode(data, &cfg); err != nil {
		t.Fatal(err)
	}
	store, err := stickermedia.NewMinioStore(nil, cfg.Sticker.Minio)
	if err != nil {
		t.Fatal("storage unavailable")
	}
	var b bytes.Buffer
	_ = png.Encode(&b, image.NewRGBA(image.Rect(0, 0, 2, 2)))
	key := "complaints/verification-" + uuid.NewString() + "/image"
	ctx := context.Background()
	defer store.RemoveKey(ctx, key)
	if err = store.PutKey(ctx, key, "image/png", b.Bytes()); err != nil {
		t.Fatal("image write failed")
	}
	got, err := store.Read(ctx, key, 1024)
	if err != nil || !bytes.Equal(got, b.Bytes()) {
		t.Fatal("image read failed")
	}
}
