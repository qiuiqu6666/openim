package admin

import (
 "context"
 "os"
 "path/filepath"
 "testing"
 "github.com/mitchellh/mapstructure"
 "github.com/openimsdk/chat/pkg/common/config"
 table "github.com/openimsdk/chat/pkg/common/db/table/chat"
 "github.com/openimsdk/tools/db/mongoutil"
 "go.mongodb.org/mongo-driver/bson"
 "go.mongodb.org/mongo-driver/mongo/options"
 "gopkg.in/yaml.v3"
)
func TestFeedbackListUsesStoredContent(t *testing.T){
 dir:=os.Getenv("COMPLAINT_TEST_CONFIG");if dir==""{t.Skip("set COMPLAINT_TEST_CONFIG for stored feedback verification")}
 b,err:=os.ReadFile(filepath.Join(dir,"mongodb.yml"));if err!=nil{t.Fatal("configuration unavailable")}
 var raw map[string]any;var cfg config.Mongo;if err=yaml.Unmarshal(b,&raw);err!=nil{t.Fatal(err)};if err=mapstructure.Decode(raw,&cfg);err!=nil{t.Fatal(err)}
 ctx:=context.Background();db,err:=mongoutil.NewMongoDB(ctx,cfg.Build());if err!=nil{t.Fatal("database unavailable")};defer db.GetDB().Client().Disconnect(ctx)
 var stored table.Feedback;if err=db.GetDB().Collection("feedback").FindOne(ctx,bson.M{},options.FindOne().SetSort(bson.D{{Key:"created_at",Value:-1}})).Decode(&stored);err!=nil{t.Fatal(err)}
 api:=&Api{identityDB:db.GetDB()}
 result,err:=api.feedbackWithNicknames(ctx,map[string]any{"total":1,"feedbacks":[]any{map[string]any{"feedbackID":stored.FeedbackID,"userID":stored.UserID}}});if err!=nil{t.Fatal(err)}
 item:=result["feedbacks"].([]any)[0].(map[string]any)
 if item["content"]!=stored.Content||item["feedbackID"]!=stored.FeedbackID||item["userID"]!=stored.UserID{t.Fatal("content or identity did not match stored feedback")}
}
