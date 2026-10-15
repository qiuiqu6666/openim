package complaints

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/mitchellh/mapstructure"
	"github.com/openimsdk/chat/pkg/common/config"
	"github.com/openimsdk/tools/db/mongoutil"
	"github.com/openimsdk/tools/db/redisutil"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/bson"
	"gopkg.in/yaml.v3"
	"image"
	"image/png"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type testMedia struct {
	objects map[string][]byte
	fail    bool
}

func (m *testMedia) PutKey(_ context.Context, k, mime string, b []byte) error {
	if m.fail {
		return errs.New("upload failed")
	}
	m.objects[k] = b
	return nil
}
func (m *testMedia) RemoveKey(_ context.Context, k string) error { delete(m.objects, k); return nil }
func (m *testMedia) Read(_ context.Context, k string, _ int64) ([]byte, error) {
	b, ok := m.objects[k]
	if !ok {
		return nil, errs.New("missing")
	}
	return b, nil
}
func (m *testMedia) Presign(_ context.Context, k string, _ time.Duration) (string, error) {
	return "https://example.test/" + k, nil
}
func TestIntegrationPersistenceAndHTTP(t *testing.T) {
	dir := os.Getenv("COMPLAINT_TEST_CONFIG")
	if dir == "" {
		t.Skip("set COMPLAINT_TEST_CONFIG for isolated MongoDB/Redis integration")
	}
	load := func(name string, out any) {
		t.Helper()
		b, e := os.ReadFile(filepath.Join(dir, name))
		if e != nil {
			t.Fatal("read test config failed")
		}
		var raw map[string]any
		if e = yaml.Unmarshal(b, &raw); e != nil {
			t.Fatal(e)
		}
		if e = mapstructure.Decode(raw, out); e != nil {
			t.Fatal(e)
		}
	}
	var mc config.Mongo
	load("mongodb.yml", &mc)
	ctx := context.Background()
	db, e := mongoutil.NewMongoDB(ctx, mc.Build())
	if e != nil {
		t.Fatal("connect test MongoDB failed")
	}
	defer db.GetDB().Client().Disconnect(ctx)
	var rc config.Redis
	load("redis.yml", &rc)
	rdb, e := redisutil.NewRedisClient(ctx, rc.Build())
	if e != nil {
		t.Fatal("connect test Redis failed")
	}
	defer rdb.Close()
	owner := "test_" + uuid.NewString()
	defer rdb.Del(ctx, "complaint:lock:"+owner, "complaint:rate:"+owner)
	collection := db.GetDB().Collection("complaints_test_" + uuid.NewString())
	defer collection.Drop(ctx)
	store, e := newStore(ctx, collection)
	if e != nil {
		t.Fatal(e)
	}
	media := &testMedia{objects: map[string][]byte{}}
	a := &API{Store: store, Media: media, Redis: rdb, Validate: func(context.Context, string, *Payload, string) error { return nil }}
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/create", func(c *gin.Context) { a.Create(c, owner, "c2c") })
	r.POST("/detail", a.Detail)
	r.POST("/screenshot", a.Screenshot)
	r.POST("/search", a.Search)
	r.POST("/update", func(c *gin.Context) { a.Update(c, "admin") })
	var pngBody bytes.Buffer
	_ = png.Encode(&pngBody, image.NewRGBA(image.Rect(0, 0, 2, 2)))
	create := func(p Payload, images int) map[string]any {
		t.Helper()
		var b bytes.Buffer
		w := multipart.NewWriter(&b)
		raw, _ := json.Marshal(p)
		_ = w.WriteField("payload", string(raw))
		for i := 0; i < images; i++ {
			f, _ := w.CreateFormFile("screenshots", "evidence.png")
			f.Write(pngBody.Bytes())
		}
		w.Close()
		req := httptest.NewRequest("POST", "/create", &b)
		req.Header.Set("Content-Type", w.FormDataContentType())
		resp := httptest.NewRecorder()
		r.ServeHTTP(resp, req)
		var body map[string]any
		if e = json.Unmarshal(resp.Body.Bytes(), &body); e != nil {
			t.Fatal(e)
		}
		return body
	}
	call := func(path string, p any) map[string]any {
		t.Helper()
		b, _ := json.Marshal(p)
		req := httptest.NewRequest("POST", path, bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		resp := httptest.NewRecorder()
		r.ServeHTTP(resp, req)
		var out map[string]any
		if e = json.Unmarshal(resp.Body.Bytes(), &out); e != nil {
			t.Fatal(e)
		}
		if out["errCode"] != float64(0) {
			t.Fatal(path, "failed", out["errCode"])
		}
		return out["data"].(map[string]any)
	}
	p := Payload{ClientRequestID: uuid.NewString(), ReportedUserID: "peer", Reason: "fraud", Content: "evidence"}
	first := create(p, 1)
	if first["errCode"] != float64(0) {
		t.Fatal("create failed", first["errCode"])
	}
	id := first["data"].(map[string]any)["complaintID"]
	replay := create(p, 1)
	if replay["errCode"] != float64(0) || replay["data"].(map[string]any)["complaintID"] != id {
		t.Fatal("retry did not replay")
	}
	if len(media.objects) != 1 {
		t.Fatal("retry uploaded extra evidence")
	}
	p.Content = "changed"
	if create(p, 1)["errCode"] == float64(0) {
		t.Fatal("conflicting retry accepted")
	}
	detail := call("/detail", map[string]any{"complaintID": id})
	if detail["content"] != "evidence" || len(detail["screenshots"].([]any)) != 1 {
		t.Fatal("evidence was not persisted")
	}
	result := call("/search", map[string]any{"chatType": "c2c", "reason": "fraud"})
	if result["total"] != float64(1) {
		t.Fatal("filter/pagination failed")
	}
	updated := call("/update", map[string]any{"complaintID": id, "status": "resolved", "note": "reviewed"})
	if updated["reviewedBy"] != "admin" {
		t.Fatal("review actor missing")
	}
	if call("/detail", map[string]any{"complaintID": id})["note"] != "reviewed" {
		t.Fatal("review not persisted")
	}
	p.ClientRequestID = uuid.NewString()
	if create(p, 6)["errCode"] == float64(0) {
		t.Fatal("six screenshots accepted")
	}
	media.fail = true
	p.ClientRequestID = uuid.NewString()
	if create(p, 1)["errCode"] == float64(0) {
		t.Fatal("upload failure accepted")
	}
	n, e := store.Rows.CountDocuments(ctx, bson.M{})
	if e != nil || n != 1 {
		t.Fatal("failed request created a row")
	}
	raw, _ := json.Marshal(map[string]any{"complaintID": id, "index": 0})
	req := httptest.NewRequest("POST", "/screenshot", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, req)
	if resp.Code != 200 || !bytes.Equal(resp.Body.Bytes(), pngBody.Bytes()) || resp.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("screenshot preview failed")
	}
	_ = time.Second
}
