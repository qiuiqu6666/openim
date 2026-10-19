package file

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

type uploadMemoryDB struct {
	db_interface.DataBase
	row *model_struct.LocalUpload
}

func (d *uploadMemoryDB) GetUpload(context.Context, string) (*model_struct.LocalUpload, error) {
	if d.row == nil {
		return nil, errors.New("not found")
	}
	copy := *d.row
	return &copy, nil
}
func (d *uploadMemoryDB) InsertUpload(_ context.Context, row *model_struct.LocalUpload) error {
	copy := *row
	d.row = &copy
	return nil
}
func (d *uploadMemoryDB) UpdateUpload(ctx context.Context, row *model_struct.LocalUpload) error {
	return d.InsertUpload(ctx, row)
}
func (d *uploadMemoryDB) DeleteUpload(context.Context, string) error { d.row = nil; return nil }

func TestUploadMultipartResumeAfterFailure(t *testing.T) {
	db := &uploadMemoryDB{}
	puts := map[string]int{}
	initCalls, completeCalls := 0, 0
	var base string
	sign := func() map[string]any {
		return map[string]any{"url": base + "/put", "parts": []any{
			map[string]any{"partNumber": 1, "query": []any{map[string]any{"key": "part", "values": []string{"1"}}}},
			map[string]any{"partNumber": 2, "query": []any{map[string]any{"key": "part", "values": []string{"2"}}}},
		}}
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var data any
		switch r.URL.Path {
		case "/object/part_limit":
			data = map[string]any{"minPartSize": 3, "maxPartSize": 100, "maxNumSize": 100}
		case "/object/initiate_multipart_upload":
			initCalls++
			data = map[string]any{"upload": map[string]any{"uploadID": "resume-id", "partSize": 3, "expireTime": time.Now().Add(24 * time.Hour).UnixMilli(), "sign": sign()}}
		case "/object/auth_sign":
			data = sign()
		case "/put":
			part := r.URL.Query().Get("part")
			puts[part]++
			body, _ := io.ReadAll(r.Body)
			expected := "abc"
			if part == "2" {
				expected = "def"
			}
			if string(body) != expected {
				t.Errorf("part %s body %q", part, body)
			}
			if part == "2" && puts[part] == 1 {
				w.WriteHeader(503)
			} else {
				w.WriteHeader(200)
			}
			return
		case "/object/complete_multipart_upload":
			completeCalls++
			data = map[string]any{"url": "completed"}
		default:
			t.Errorf("unexpected route %s", r.URL.Path)
			w.WriteHeader(404)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data})
	}))
	defer server.Close()
	base = server.URL
	path := filepath.Join(t.TempDir(), "resume.bin")
	if err := os.WriteFile(path, []byte("abcdef"), 0600); err != nil {
		t.Fatal(err)
	}
	config := &ccontext.GlobalConfig{UserID: "test", IMConfig: sdk_struct.IMConfig{ApiAddr: base}}
	ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "resume-test"), config)
	f := NewFile(db, "test")
	result, err := f.UploadFile(ctx, &UploadFileReq{Filepath: path, Name: "resume.bin"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.URL != "completed" || puts["1"] != 1 || puts["2"] != 2 || initCalls != 1 || completeCalls != 1 || db.row != nil {
		t.Fatalf("resume: result=%v puts=%v init=%d complete=%d cache=%v", result, puts, initCalls, completeCalls, db.row)
	}
}
