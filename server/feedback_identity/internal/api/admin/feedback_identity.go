package admin

import (
	"context"
	"encoding/json"
	table "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/complaints"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// Decorate the existing response without changing its protocol or historical records.
func (o *Api) feedbackWithNicknames(ctx context.Context, payload any) (map[string]any, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	var data map[string]any
	if err = json.Unmarshal(raw, &data); err != nil {
		return nil, err
	}
	items := []map[string]any{}
	if list, ok := data["feedbacks"].([]any); ok {
		for _, item := range list {
			if row, ok := item.(map[string]any); ok {
				items = append(items, row)
			}
		}
	} else if _, ok := data["userID"].(string); ok {
		items = append(items, data)
	}
	if _, isList := data["feedbacks"]; isList && len(items) > 0 && o.identityDB != nil {
		ids := make([]string, 0, len(items))
		for _, row := range items {
			if id, ok := row["feedbackID"].(string); ok && id != "" {
				ids = append(ids, id)
			}
		}
		if len(ids) > 0 {
			cur, err := o.identityDB.Collection("feedback").Find(ctx, bson.M{"feedback_id": bson.M{"$in": ids}}, options.Find().SetProjection(bson.M{"feedback_id": 1, "content": 1}))
			if err != nil {
				return nil, err
			}
			defer cur.Close(ctx)
			contents := map[string]string{}
			for cur.Next(ctx) {
				var row table.Feedback
				if err = cur.Decode(&row); err != nil {
					return nil, err
				}
				contents[row.FeedbackID] = row.Content
			}
			if err = cur.Err(); err != nil {
				return nil, err
			}
			for _, row := range items {
				id, _ := row["feedbackID"].(string)
				row["content"] = contents[id]
			}
		}
	}
	refs := make([]*complaints.Record, len(items))
	for i, row := range items {
		id, _ := row["userID"].(string)
		refs[i] = &complaints.Record{UserID: id}
	}
	if len(refs) > 0 && o.complaints != nil && o.complaints.Enrich != nil {
		if err = o.complaints.Enrich(ctx, refs); err != nil {
			return nil, err
		}
	}
	for i, row := range items {
		row["userNickname"] = refs[i].UserNickname
	}
	return data, nil
}
