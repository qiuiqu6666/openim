package uploadrelay

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/openimsdk/open-im-server/v3/pkg/common/config"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/objectstorage"
	"github.com/openimsdk/protocol/third"
)

// Uses the configured administrator only to exercise storage APIs. It creates
// no chat messages, user sessions, or completed objects; the temporary key is deleted.
func TestLiveCOSAuthenticatedRelay(t *testing.T) {
	base := os.Getenv("UPLOAD_FALLBACK_LIVE_API")
	if base == "" {
		t.Skip("explicit live API required")
	}
	var share struct {
		Secret string   `mapstructure:"secret"`
		Admin  []string `mapstructure:"imAdminUserID"`
	}
	var cfg struct {
		Object struct {
			Cos config.Cos `mapstructure:"cos"`
		} `mapstructure:"object"`
	}
	configRoot := "/srv/99chat-production/app/config/open-im-server/"
	if config.LoadConfig(configRoot+"share.yml", "FALLBACK_LIVE_SHARE", &share) != nil || len(share.Admin) == 0 || config.LoadConfig(configRoot+"openim-rpc-third.yml", "FALLBACK_LIVE_THIRD", &cfg) != nil {
		t.Fatal("configuration unavailable")
	}
	regionalHost := RegionalHost
	hk := os.Getenv("UPLOAD_FALLBACK_LIVE_HK") == "1"
	if hk {
		if cfg.Object.Cos.Legacy == nil {
			t.Fatal("backup configuration unavailable")
		}
		cfg.Object.Cos = *cfg.Object.Cos.Legacy
		regionalHost = HongKongHost
	}
	backend, err := objectstorage.NewCOS(*cfg.Object.Cos.Build(), "")
	if err != nil {
		t.Fatal("storage initialization failed")
	}
	client := &http.Client{Timeout: 30 * time.Second}
	clientIP := "223.5.5.5"
	post := func(path, token string, body any, out any) {
		b, _ := json.Marshal(body)
		req, _ := http.NewRequest("POST", base+path, bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("operationID", "upload-fallback-live-api")
		req.Header.Set("token", token)
		req.Header.Set("X-Real-IP", clientIP)
		resp, err := client.Do(req)
		if err != nil {
			t.Fatal("API transport failed")
		}
		defer resp.Body.Close()
		var envelope struct {
			ErrCode int             `json:"errCode"`
			Data    json.RawMessage `json:"data"`
		}
		if json.NewDecoder(resp.Body).Decode(&envelope) != nil || envelope.ErrCode != 0 || len(envelope.Data) == 0 {
			t.Fatalf("API %s rejected request", path)
		}
		if json.Unmarshal(envelope.Data, out) != nil {
			t.Fatal("invalid API response")
		}
	}
	var auth struct {
		Token string `json:"token"`
	}
	post("/auth/get_admin_token", "", map[string]any{"secret": share.Secret, "userID": share.Admin[0]}, &auth)
	if auth.Token == "" {
		t.Fatal("authentication failed")
	}
	payload := []byte(fmt.Sprintf("authenticated-upload-fallback-%d", time.Now().UnixNano()))
	partHash := md5.Sum(payload)
	hash := md5.Sum([]byte(hex.EncodeToString(partHash[:])))
	name := share.Admin[0] + "/upload-fallback-check"
	if hk {
		name = share.Admin[0] + "/__cos_hk__/upload-fallback-" + fmt.Sprint(time.Now().UnixNano())
	}
	var upload third.InitiateMultipartUploadResp
	post("/object/initiate_multipart_upload", auth.Token, map[string]any{"hash": hex.EncodeToString(hash[:]), "size": len(payload), "partSize": 1048576, "maxParts": 1, "name": name, "contentType": "application/octet-stream"}, &upload)
	if upload.Upload == nil || upload.Upload.Sign == nil || len(upload.Upload.Sign.Parts) != 1 {
		t.Fatal("missing single-part upload")
	}
	checkPreference := func(parts []*third.SignPart, want bool) {
		t.Helper()
		for _, part := range parts {
			for _, h := range part.Header {
				if !strings.EqualFold(h.Key, TargetHeader) || len(h.Values) == 0 {
					continue
				}
				var preference struct {
					PreferRegional *bool `json:"preferRegional"`
				}
				if json.Unmarshal([]byte(h.Values[0]), &preference) != nil || preference.PreferRegional == nil || *preference.PreferRegional != want {
					t.Fatal("incorrect deployed region preference")
				}
				return
			}
		}
		t.Fatal("missing route metadata")
	}
	checkPreference(upload.Upload.Sign.Parts, true)
	// Small objects use presigned PUT and deliberately cannot renew with AuthSign.
	// Create an empty multipart session for renewal checks and always abort it.
	var multipart third.InitiateMultipartUploadResp
	post("/object/initiate_multipart_upload", auth.Token, map[string]any{"hash": hex.EncodeToString(hash[:]), "size": 64 * 1024 * 1024, "maxParts": 1, "name": name + "-multipart", "contentType": "application/octet-stream"}, &multipart)
	if multipart.Upload == nil {
		t.Fatal("missing multipart session")
	}
	idJSON, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(multipart.Upload.UploadID, "hk:"))
	var multipartID struct {
		ID  string `json:"b"`
		Key string `json:"c"`
	}
	if err != nil || json.Unmarshal(idJSON, &multipartID) != nil || multipartID.ID == "" {
		t.Fatal("invalid multipart session")
	}
	defer func() {
		if backend.AbortMultipartUpload(context.Background(), multipartID.ID, multipartID.Key) != nil {
			t.Error("multipart cleanup failed")
		}
	}()
	for _, sample := range []struct {
		ip   string
		want bool
	}{{"8.8.8.8", false}, {"2400:3200::1", true}, {"2001:4860:4860::8888", false}, {"168.95.1.1", false}, {"127.0.0.1", false}} {
		clientIP = sample.ip
		var renewed third.AuthSignResp
		post("/object/auth_sign", auth.Token, map[string]any{"uploadID": multipart.Upload.UploadID, "partNumbers": []int{1}}, &renewed)
		checkPreference(renewed.Parts, sample.want)
	}
	metadata := ""
	for _, h := range upload.Upload.Sign.Parts[0].Header {
		if strings.EqualFold(h.Key, TargetHeader) && len(h.Values) > 0 {
			metadata = h.Values[0]
		}
	}
	var target Target
	if json.Unmarshal([]byte(metadata), &target) != nil {
		t.Fatal("deployed signer did not return fallback")
	}
	u, err := url.Parse(target.URL)
	if err != nil || u.Host != regionalHost {
		t.Fatal("invalid deployed regional target")
	}
	defer func() {
		if backend.DeleteObject(context.Background(), strings.TrimPrefix(u.Path, "/")) != nil {
			t.Error("temporary upload cleanup failed")
		}
	}()
	req, _ := http.NewRequest("POST", base+"/object/upload_relay", bytes.NewReader(payload))
	req.Header.Set("operationID", "upload-fallback-live-api")
	req.Header.Set("token", auth.Token)
	req.Header.Set(TargetHeader, metadata)
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal("relay transport failed")
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 204 {
		t.Fatalf("relay status %d", resp.StatusCode)
	}
	u.RawQuery = ""
	resp, err = client.Get(u.String())
	if err != nil {
		t.Fatal("stored content read failed")
	}
	stored, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil || resp.StatusCode != 200 || !bytes.Equal(stored, payload) {
		t.Fatal("stored content differs")
	}
	if hk {
		cleanup := prepareLiveMappingCleanup(t, cfg.Object.Cos, backend, name, hex.EncodeToString(hash[:]))
		defer cleanup()
		var completed third.CompleteMultipartUploadResp
		post("/object/complete_multipart_upload", auth.Token, map[string]any{"uploadID": upload.Upload.UploadID, "parts": []string{hex.EncodeToString(partHash[:])}, "name": name, "contentType": "application/octet-stream"}, &completed)
		if !strings.HasPrefix(completed.Url, "https://"+HongKongHost+"/") {
			t.Fatal("completion did not preserve HK storage")
		}
		var access third.AccessURLResp
		post("/object/access_url", auth.Token, map[string]any{"name": name}, &access)
		for _, raw := range []string{completed.Url, access.Url} {
			response, e := client.Get(raw)
			if e != nil {
				t.Fatal("completed object unavailable")
			}
			content, e := io.ReadAll(response.Body)
			response.Body.Close()
			if e != nil || response.StatusCode != 200 || !bytes.Equal(content, payload) {
				t.Fatal("completed bytes differ")
			}
		}
	}

}
