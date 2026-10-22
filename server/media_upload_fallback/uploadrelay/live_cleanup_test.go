package uploadrelay

import (
	"context"
	"testing"
	"time"

	"github.com/openimsdk/open-im-server/v3/pkg/common/config"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/controller"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/database/mgo"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/objectstorage"
	"github.com/openimsdk/tools/db/mongoutil"
	"github.com/openimsdk/tools/db/redisutil"
	"github.com/openimsdk/tools/s3"
)

// Delete only the unique test-owned logical mapping and content hash.
func prepareLiveMappingCleanup(t *testing.T, cosConfig config.Cos, backend *objectstorage.COS, name, hash string) func() {
	t.Helper()
	var mongoConfig config.Mongo
	var redisConfig config.Redis
	base := "/srv/99chat-production/app/config/open-im-server/"
	if config.LoadConfig(base+"mongodb.yml", "DISASTER_LIVE_MONGO", &mongoConfig) != nil || config.LoadConfig(base+"redis.yml", "DISASTER_LIVE_REDIS", &redisConfig) != nil {
		t.Fatal("cleanup configuration unavailable")
	}
	ctx := context.Background()
	mg, err := mongoutil.NewMongoDB(ctx, mongoConfig.Build())
	if err != nil {
		t.Fatal("cleanup database unavailable")
	}
	rd, err := redisutil.NewRedisClient(ctx, redisConfig.Build())
	if err != nil {
		t.Fatal("cleanup cache unavailable")
	}
	db, err := mgo.NewS3Mongo(mg.GetDB())
	if err != nil {
		rd.Close()
		t.Fatal("cleanup store unavailable")
	}
	var storage s3.Interface = backend
	if cosConfig.EngineName != "" {
		storage = &objectstorage.NamedEngine{Interface: backend, Name: cosConfig.EngineName}
	}
	store := controller.NewS3Database(rd, storage, db)
	return func() {
		defer rd.Close()
		clean, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		obj, err := db.Take(clean, storage.Engine(), name)
		if err != nil {
			t.Error("test mapping not found during cleanup")
			return
		}
		if err := backend.DeleteObject(clean, obj.Key); err != nil {
			t.Error("completed test content cleanup failed")
		}
		if err := store.DeleteSpecifiedData(clean, storage.Engine(), []string{name}); err != nil {
			t.Error("test mapping cleanup failed")
		}
		if err := store.DelS3Key(clean, storage.Engine(), obj.Key); err != nil {
			t.Error("test cache cleanup failed")
		}
	}
}
