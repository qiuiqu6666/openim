package db

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

func Test_BatchInsertNotificationSeq(t *testing.T) {
	ctx := context.Background()
	db, err := NewDataBase(ctx, "notification-test", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close(ctx) })
	// log.ZError(ctx, "DB err test", nil, "key", "vale")
	notificationSeqs := []*model_struct.NotificationSeqs{
		{
			ConversationID: "n_2882899447_69085919821",
			Seq:            2,
		},
		{
			ConversationID: "n_2882899447_69085919822",
			Seq:            3,
		},
	}
	err = db.BatchInsertNotificationSeq(ctx, notificationSeqs)
	if err != nil {
		t.Fatal(err)
	}

}
