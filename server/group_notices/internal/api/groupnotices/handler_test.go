package groupnotices

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/openimsdk/protocol/constant"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

func TestCursorScopeAndValidation(t *testing.T) {
	c := Cursor{"a", 100, 2, 99, "g", "u"}
	if _, e := decodeCursor(c.encode(), "b", 101); e == nil {
		t.Fatal("cross-account cursor accepted")
	}
	if _, e := decodeCursor(c.encode(), "a", 90); e == nil {
		t.Fatal("future cursor accepted")
	}
	got, e := decodeCursor(c.encode(), "a", 101)
	if e != nil || got != c {
		t.Fatal(got, e)
	}
}
func TestServerNoticesIntegration(t *testing.T) {
	uri := os.Getenv("NOTICE_TEST_MONGO")
	if uri == "" {
		t.Skip("isolated MongoDB required")
	}
	ctx := context.Background()
	client, e := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if e != nil {
		t.Fatal(e)
	}
	defer client.Disconnect(ctx)
	// This generated test database is never the application database.
	db := client.Database(fmt.Sprintf("notice_test_%d", time.Now().UnixNano()))
	defer db.Drop(ctx)
	if e = EnsureIndexes(ctx, db); e != nil {
		t.Fatal(e)
	}
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(func(c *gin.Context) {
		if u := c.GetHeader("Test-User"); u != "" {
			c.Set(constant.OpUserID, u)
		}
	})
	Register(r, db)
	call := func(owner, path string, body any) map[string]any {
		t.Helper()
		b, _ := json.Marshal(body)
		req := httptest.NewRequest("POST", "/group/notices/"+path, bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Test-User", owner)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		var out map[string]any
		if e := json.Unmarshal(w.Body.Bytes(), &out); e != nil {
			t.Fatalf("decode %s: %s", path, w.Body.String())
		}
		return out
	}
	data := func(owner, path string, body any) map[string]any {
		t.Helper()
		out := call(owner, path, body)
		if out["errCode"] != float64(0) {
			t.Fatalf("%s failed: %v", path, out)
		}
		return out["data"].(map[string]any)
	}
	if call("", "list", bson.M{})["errCode"] == float64(0) {
		t.Fatal("anonymous accepted")
	}
	_, e = db.Collection("group_member").InsertMany(ctx, []any{bson.M{"user_id": "admin", "group_id": "g", "role_level": constant.GroupAdmin}, bson.M{"user_id": "other", "group_id": "g", "role_level": constant.GroupAdmin}})
	if e != nil {
		t.Fatal(e)
	}
	base := time.Now().Add(-time.Hour).Truncate(time.Millisecond)
	docs := make([]any, 20000)
	for i := range docs {
		docs[i] = bson.M{"group_id": "g", "user_id": fmt.Sprintf("u%05d", i), "req_time": base.Add(time.Duration(i/3) * time.Millisecond), "handle_result": 0}
	}
	if _, e = db.Collection("group_request").InsertMany(ctx, docs); e != nil {
		t.Fatal(e)
	}
	firstAt := time.Now()
	first := data("admin", "list", bson.M{"limit": 20})
	t.Logf("20,000 records first page: %s", time.Since(firstAt))
	if len(first["items"].([]any)) != 20 {
		t.Fatal("not bounded")
	}
	second := data("admin", "list", bson.M{"cursor": first["nextCursor"], "limit": 20})
	seen := map[string]bool{}
	for _, p := range []map[string]any{first, second} {
		for _, row := range p["items"].([]any) {
			id := row.(map[string]any)["userID"].(string)
			if seen[id] {
				t.Fatal("duplicate cursor row", id)
			}
			seen[id] = true
		}
	}
	if call("other", "list", bson.M{"cursor": first["nextCursor"]})["errCode"] == float64(0) {
		t.Fatal("cursor leaked between accounts")
	}
	victim := first["items"].([]any)[0].(map[string]any)
	detailReq := bson.M{"groupID": "g", "userID": victim["userID"], "reqTime": victim["reqTime"]}
	if data("admin", "detail", detailReq)["item"] == nil {
		t.Fatal("authorized detail missing")
	}
	if data("outsider", "detail", detailReq)["item"] != nil {
		t.Fatal("detail leaked")
	}

	data("admin", "delete", bson.M{"groupID": "g", "userID": victim["userID"], "reqTime": victim["reqTime"]})
	if data("admin", "list", bson.M{"cursor": first["nextCursor"]})["reset"] != true {
		t.Fatal("stale cursor survived delete")
	}
	fresh := data("admin", "list", bson.M{})
	if fresh["items"].([]any)[0].(map[string]any)["userID"] == victim["userID"] {
		t.Fatal("deleted row returned on second device")
	}
	if data("other", "list", bson.M{})["items"].([]any)[0].(map[string]any)["userID"] != victim["userID"] {
		t.Fatal("other administrator affected")
	}
	state := data("admin", "state", bson.M{})
	if state["unreadCount"] != float64(19999) {
		t.Fatal(state)
	}
	data("admin", "read", bson.M{"through": first["snapshotTime"]})
	if data("admin", "state", bson.M{})["unreadCount"] != float64(0) {
		t.Fatal("read acknowledgement not synced")
	}
	clearAt := time.Now()
	data("admin", "clear", bson.M{"through": first["snapshotTime"]})
	t.Logf("clear 20,000 records: %s", time.Since(clearAt))
	if len(data("admin", "list", bson.M{})["items"].([]any)) != 0 {
		t.Fatal("clear did not cover unloaded pages")
	}
	count, _ := db.Collection("group_request").CountDocuments(ctx, bson.M{})
	if count != 20000 {
		t.Fatal("approval records destroyed")
	}
	time.Sleep(3 * time.Millisecond)
	newTime := time.Now().Truncate(time.Millisecond)
	db.Collection("group_request").InsertOne(ctx, bson.M{"group_id": "g", "user_id": "new", "req_time": newTime, "handle_result": 0})
	latest := data("admin", "list", bson.M{})
	if len(latest["items"].([]any)) != 1 {
		t.Fatal("new request hidden after clear", latest)
	}
	// Retry old clear/read boundaries never advances over a later request.
	data("admin", "clear", bson.M{"through": first["snapshotTime"]})
	data("admin", "read", bson.M{"through": first["snapshotTime"]})
	if data("admin", "state", bson.M{})["unreadCount"] != float64(1) {
		t.Fatal("new request lost")
	}
	if call("admin", "clear", bson.M{"through": time.Now().Add(time.Hour).UnixMilli()})["errCode"] == float64(0) {
		t.Fatal("future clear accepted")
	}
	// Legacy local clears import idempotently without hiding subsequent requests.
	migration := bson.M{"through": first["snapshotTime"], "items": bson.A{bson.M{"groupID": "g", "userID": victim["userID"], "reqTime": victim["reqTime"]}}}
	data("other", "migrate", migration)
	data("other", "migrate", migration)
	if len(data("other", "list", bson.M{})["items"].([]any)) != 1 {
		t.Fatal("legacy migration lost new request")
	}
	// Removed admins no longer receive the group's requests.
	db.Collection("group_member").DeleteOne(ctx, bson.M{"user_id": "admin"})
	if len(data("admin", "list", bson.M{})["items"].([]any)) != 0 {
		t.Fatal("former admin retained access")
	}
}
