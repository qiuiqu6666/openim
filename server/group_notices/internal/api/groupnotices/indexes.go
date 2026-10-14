package groupnotices

import (
	"context"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func EnsureIndexes(ctx context.Context, db *mongo.Database) error {
	for _, spec := range []struct {
		name    string
		indexes []mongo.IndexModel
	}{
		{"group_request", []mongo.IndexModel{
			{Keys: bson.D{{Key: "user_id", Value: 1}, {Key: "req_time", Value: -1}, {Key: "group_id", Value: -1}}, Options: options.Index().SetName("notice_applicant_time")},
			{Keys: bson.D{{Key: "group_id", Value: 1}, {Key: "req_time", Value: -1}, {Key: "user_id", Value: -1}}, Options: options.Index().SetName("notice_group_time")},
			{Keys: bson.D{{Key: "group_id", Value: 1}, {Key: "handle_result", Value: 1}, {Key: "req_time", Value: -1}, {Key: "user_id", Value: 1}}, Options: options.Index().SetName("notice_unread")},
		}},
		{"group_member", []mongo.IndexModel{{Keys: bson.D{{Key: "user_id", Value: 1}, {Key: "role_level", Value: 1}, {Key: "group_id", Value: 1}}, Options: options.Index().SetName("notice_managed_groups")}}},
		{dismissals, []mongo.IndexModel{{Keys: bson.D{{Key: "owner", Value: 1}, {Key: "group_id", Value: 1}, {Key: "user_id", Value: 1}, {Key: "req_time", Value: 1}}, Options: options.Index().SetName("notice_identity").SetUnique(true)}}},
	} {
		if _, e := db.Collection(spec.name).Indexes().CreateMany(ctx, spec.indexes); e != nil {
			return e
		}
	}
	return nil
}
