package complaints

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"time"
)

type Store struct{ Rows *mongo.Collection }

func New(ctx context.Context, db *mongo.Database) (*Store, error) {
	return newStore(ctx, db.Collection("chat_complaints"))
}
func newStore(ctx context.Context, collection *mongo.Collection) (*Store, error) {
	s := &Store{Rows: collection}
	_, err := s.Rows.Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "user_id", Value: 1}, {Key: "client_request_id", Value: 1}}, Options: options.Index().SetUnique(true)},
		{Keys: bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: -1}}},
		{Keys: bson.D{{Key: "user_id", Value: 1}, {Key: "created_at", Value: -1}}},
		{Keys: bson.D{{Key: "status", Value: 1}, {Key: "chat_type", Value: 1}, {Key: "created_at", Value: -1}}},
	})
	return s, err
}
func (s *Store) Replay(ctx context.Context, owner, request, digest string) (*Record, error) {
	var row Record
	err := s.Rows.FindOne(ctx, bson.M{"user_id": owner, "client_request_id": request}).Decode(&row)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if row.Digest != digest {
		return nil, ErrConflict.WrapMsg("complaint changed; submit with a new request ID")
	}
	return &row, nil
}
func (s *Store) Insert(ctx context.Context, row *Record) (*Record, error) {
	row.ID = "cp_" + uuid.NewString()
	row.Status = "received"
	row.CreatedAt = time.Now().UnixMilli()
	row.UpdatedAt = row.CreatedAt
	_, err := s.Rows.InsertOne(ctx, row)
	if mongo.IsDuplicateKeyError(err) {
		return s.Replay(ctx, row.UserID, row.ClientRequestID, row.Digest)
	}
	return row, err
}

type Search struct {
	UserID         string `json:"userID"`
	ReportedUserID string `json:"reportedUserID"`
	GroupID        string `json:"groupID"`
	ChatType       string `json:"chatType"`
	Reason         string `json:"reason"`
	Status         string `json:"status"`
	Pagination     struct {
		PageNumber int64 `json:"pageNumber"`
		ShowNumber int64 `json:"showNumber"`
	} `json:"pagination"`
}

func (s *Store) Search(ctx context.Context, q Search) ([]Record, int64, error) {
	f := bson.M{}
	for k, v := range map[string]string{"user_id": q.UserID, "reported_user_id": q.ReportedUserID, "group_id": q.GroupID, "chat_type": q.ChatType, "reason": q.Reason, "status": q.Status} {
		if v != "" {
			f[k] = v
		}
	}
	page, size := q.Pagination.PageNumber, q.Pagination.ShowNumber
	if page < 1 {
		page = 1
	}
	if size < 1 || size > 100 {
		size = 20
	}
	if page > 100000 {
		page = 100000
	}
	total, err := s.Rows.CountDocuments(ctx, f)
	if err != nil {
		return nil, 0, err
	}
	cur, err := s.Rows.Find(ctx, f, options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: -1}}).SetSkip((page-1)*size).SetLimit(size))
	if err != nil {
		return nil, 0, err
	}
	defer cur.Close(ctx)
	rows := []Record{}
	err = cur.All(ctx, &rows)
	return rows, total, err
}
func (s *Store) Detail(ctx context.Context, id string) (*Record, error) {
	var r Record
	err := s.Rows.FindOne(ctx, bson.M{"_id": id}).Decode(&r)
	return &r, err
}
func (s *Store) Update(ctx context.Context, id, status, note, admin string) (*Record, error) {
	if !ValidStatus(status) || len([]rune(note)) > 2000 {
		return nil, errs.ErrArgs.WrapMsg("invalid complaint status or note")
	}
	var r Record
	err := s.Rows.FindOneAndUpdate(ctx, bson.M{"_id": id}, bson.M{"$set": bson.M{"status": status, "note": note, "updated_at": time.Now().UnixMilli(), "reviewed_by": admin}}, options.FindOneAndUpdate().SetReturnDocument(options.After)).Decode(&r)
	return &r, err
}
