package admin

import (
	"context"
	"github.com/openimsdk/chat/pkg/complaints"
	"testing"
)

func TestFeedbackNamesPreserveListAndDetail(t *testing.T) {
	calls := 0
	api := &Api{complaints: &complaints.API{Enrich: func(_ context.Context, rows []*complaints.Record) error {
		calls++
		for _, r := range rows {
			r.UserNickname = "Current nickname"
		}
		return nil
	}}}
	list, err := api.feedbackWithNicknames(context.Background(), map[string]any{"feedbacks": []any{map[string]any{"userID": "im_user", "feedbackID": "fb_1", "status": "received"}}, "total": 1})
	if err != nil {
		t.Fatal(err)
	}
	row := list["feedbacks"].([]any)[0].(map[string]any)
	if row["userNickname"] != "Current nickname" || row["userID"] != "im_user" || row["feedbackID"] != "fb_1" || list["total"] != float64(1) {
		t.Fatal("list metadata changed")
	}
	detail, err := api.feedbackWithNicknames(context.Background(), map[string]any{"userID": "im_user", "content": "original", "screenshots": []any{map[string]any{"url": "evidence"}}})
	if err != nil || detail["userNickname"] != "Current nickname" || detail["content"] != "original" || len(detail["screenshots"].([]any)) != 1 || calls != 2 {
		t.Fatal("detail was not preserved")
	}
}
func TestEmptyFeedbackDoesNotQueryDirectory(t *testing.T) {
	api := &Api{complaints: &complaints.API{Enrich: func(context.Context, []*complaints.Record) error { t.Fatal("empty page queried directory"); return nil }}}
	if _, err := api.feedbackWithNicknames(context.Background(), map[string]any{"feedbacks": []any{}, "total": 0}); err != nil {
		t.Fatal(err)
	}
}
