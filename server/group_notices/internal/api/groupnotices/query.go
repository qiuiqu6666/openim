// Package groupnotices owns account-scoped notice visibility, not approvals.
package groupnotices

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"time"
)

const states = "group_notice_state"
const dismissals = "group_notice_dismissal"

type State struct {
	UserID         string `bson:"_id" json:"-"`
	ClearedThrough int64  `bson:"cleared_through" json:"clearedThrough"`
	ReadThrough    int64  `bson:"read_through" json:"readThrough"`
	Revision       int64  `bson:"revision" json:"revision"`
}
type Cursor struct {
	Owner    string `json:"o"`
	Snapshot int64  `json:"s"`
	Revision int64  `json:"v"`
	Time     int64  `json:"t"`
	Group    string `json:"g"`
	User     string `json:"u"`
}

func (c Cursor) encode() string {
	b, _ := json.Marshal(c)
	return base64.RawURLEncoding.EncodeToString(b)
}
func decodeCursor(raw, owner string, now int64) (Cursor, error) {
	var c Cursor
	if len(raw) > 4096 {
		return c, fmt.Errorf("invalid cursor")
	}
	b, e := base64.RawURLEncoding.DecodeString(raw)
	if e != nil {
		return c, e
	}
	e = json.Unmarshal(b, &c)
	if e != nil || c.Owner != owner || c.Snapshot <= 0 || c.Snapshot > now || c.Time <= 0 || c.Time > c.Snapshot || c.Group == "" || c.User == "" {
		return c, fmt.Errorf("invalid cursor")
	}
	return c, nil
}
func visibility(owner string, groups []string, state State, snapshot int64, cursor *Cursor, unread bool) bson.M {
	floor := state.ClearedThrough
	if unread && state.ReadThrough > floor {
		floor = state.ReadThrough
	}
	scope := bson.M{"$or": bson.A{bson.M{"user_id": owner}, bson.M{"group_id": bson.M{"$in": groups}}}}
	if unread {
		scope = bson.M{"group_id": bson.M{"$in": groups}, "handle_result": 0, "user_id": bson.M{"$ne": owner}}
	}
	clauses := bson.A{scope, bson.M{"req_time": bson.M{"$gt": time.UnixMilli(floor), "$lte": time.UnixMilli(snapshot)}}}
	if cursor != nil {
		t := time.UnixMilli(cursor.Time)
		clauses = append(clauses, bson.M{"$or": bson.A{
			bson.M{"req_time": bson.M{"$lt": t}},
			bson.M{"req_time": t, "group_id": bson.M{"$lt": cursor.Group}},
			bson.M{"req_time": t, "group_id": cursor.Group, "user_id": bson.M{"$lt": cursor.User}},
		}})
	}
	return bson.M{"$and": clauses}
}
func pipeline(owner string, filter bson.M, limit int, count bool) mongo.Pipeline {
	p := mongo.Pipeline{{{Key: "$match", Value: filter}}}
	if !count {
		p = append(p, bson.D{{Key: "$sort", Value: bson.D{{Key: "req_time", Value: -1}, {Key: "group_id", Value: -1}, {Key: "user_id", Value: -1}}}})
	}
	p = append(p, bson.D{{Key: "$lookup", Value: bson.M{
		"from": dismissals, "let": bson.M{"g": "$group_id", "u": "$user_id", "t": "$req_time"},
		"pipeline": bson.A{bson.M{"$match": bson.M{"owner": owner, "$expr": bson.M{"$and": bson.A{
			bson.M{"$eq": bson.A{"$group_id", "$$g"}}, bson.M{"$eq": bson.A{"$user_id", "$$u"}}, bson.M{"$eq": bson.A{"$req_time", "$$t"}},
		}}}}, bson.M{"$limit": 1}}, "as": "_dismissed",
	}}}, bson.D{{Key: "$match", Value: bson.M{"_dismissed.0": bson.M{"$exists": false}}}})
	if count {
		return append(p, bson.D{{Key: "$count", Value: "count"}})
	}
	return append(p, bson.D{{Key: "$limit", Value: limit + 1}}, bson.D{{Key: "$project", Value: bson.M{"_dismissed": 0}}})
}
