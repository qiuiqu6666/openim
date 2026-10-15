package admin

import (
	"context"
	"github.com/mitchellh/mapstructure"
	"github.com/openimsdk/chat/pkg/common/config"
	"github.com/openimsdk/chat/pkg/common/imapi"
	"github.com/openimsdk/chat/pkg/complaints"
	"github.com/openimsdk/protocol/constant"
	"github.com/openimsdk/tools/db/mongoutil"
	"gopkg.in/yaml.v3"
	"os"
	"path/filepath"
	"testing"
)

func TestComplaintNamesFromCurrentDirectory(t *testing.T) {
	dir := os.Getenv("COMPLAINT_TEST_CONFIG")
	if dir == "" {
		t.Skip("set COMPLAINT_TEST_CONFIG for real directory verification")
	}
	load := func(name string, out any) {
		t.Helper()
		b, e := os.ReadFile(filepath.Join(dir, name))
		if e != nil {
			t.Fatal("configuration unavailable")
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
	var share config.Share
	load("mongodb.yml", &mc)
	load("share.yml", &share)
	ctx := context.WithValue(context.Background(), constant.OperationID, "complaint-names-verification")
	db, err := mongoutil.NewMongoDB(ctx, mc.Build())
	if err != nil {
		t.Fatal("directory unavailable")
	}
	defer db.GetDB().Client().Disconnect(ctx)
	api := &Api{identityDB: db.GetDB(), imApiCaller: imapi.New(share.OpenIM.ApiURL, share.OpenIM.Secret, share.OpenIM.AdminUserID)}
	store := &complaints.Store{Rows: db.GetDB().Collection("chat_complaints")}
	rows, _, err := store.Search(ctx, complaints.Search{ChatType: "group"})
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) == 0 {
		t.Skip("no group complaints available")
	}
	row := &rows[0]
	beforeUser, beforePeer, beforeGroup := row.UserID, row.ReportedUserID, row.GroupID
	if err = api.enrichComplaints(ctx, []*complaints.Record{row}, share.OpenIM.ApiURL); err != nil {
		t.Fatal(err)
	}
	if row.UserNickname == "" || row.ReportedUserNickname == "" || row.GroupName == "" {
		t.Fatal("current names missing from existing complaint")
	}
	if row.UserID != beforeUser || row.ReportedUserID != beforePeer || row.GroupID != beforeGroup {
		t.Fatal("identity changed during presentation enrichment")
	}
	t.Log("Existing complaint resolved reporter nickname, reported nickname and group name; all IDs preserved")
}
