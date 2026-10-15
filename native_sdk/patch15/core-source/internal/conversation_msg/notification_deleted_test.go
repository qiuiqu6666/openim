package conversation_msg

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/internal/relation"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type notificationCheckpointDB struct {
	db_interface.DataBase
	seq        int64
	err        error
	profileErr error
}

func (d *notificationCheckpointDB) GetVersionSync(context.Context, string, string) (*model_struct.LocalVersionSync, error) {
	return &model_struct.LocalVersionSync{VersionID: "friends", Version: 1}, d.profileErr
}
func (d *notificationCheckpointDB) GetFriendInfoList(context.Context, []string) ([]*model_struct.LocalFriend, error) {
	return nil, nil
}

func TestFriendNotificationFailureDoesNotAdvanceCheckpoint(t *testing.T) {
	failure := errors.New("temporary friend storage failure")
	d := &notificationCheckpointDB{seq: 1, profileErr: failure}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		_, _ = w.Write([]byte(`{"errCode":0,"data":{"versionID":"friends","version":1}}`))
	}))
	defer srv.Close()
	ctx := ccontext.WithInfo(context.WithValue(context.Background(), "operationID", "friend-notification-retry"), &ccontext.GlobalConfig{UserID: "self", IMConfig: sdk_struct.IMConfig{ApiAddr: srv.URL}})
	c := &Conversation{db: d, relation: relation.NewFriend("self", d, nil, nil)}
	msg := &sdkws.MsgData{Seq: 2, ContentType: constant.FriendInfoUpdatedNotification, Content: []byte(`{"detail":"{\"userID\":\"peer\"}"}`)}
	cmd := common.Cmd2Value{Ctx: ctx, Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_friend": {Msgs: []*sdkws.MsgData{msg}}}}}
	if err := c.doNotificationManager(cmd); !errors.Is(err, failure) || d.seq != 1 {
		t.Fatalf("friend failure was acknowledged: err=%v seq=%d", err, d.seq)
	}
	d.profileErr = nil
	if err := c.doNotificationManager(cmd); err != nil || d.seq != 2 {
		t.Fatalf("same notification did not retry successfully: err=%v seq=%d", err, d.seq)
	}
}

func (d *notificationCheckpointDB) SetNotificationSeq(_ context.Context, _ string, seq int64) error {
	if d.err != nil {
		return d.err
	}
	d.seq = seq
	return nil
}

func TestDeletedNotificationPageCheckpoint(t *testing.T) {
	for _, tc := range []struct {
		name       string
		live       bool
		writeError bool
	}{
		{name: "deleted placeholders advance checkpoint"},
		{name: "unknown live notification still fails", live: true},
		{name: "checkpoint failure remains retryable", writeError: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := &notificationCheckpointDB{seq: 1}
			if tc.writeError {
				d.err = errors.New("disk failure")
			}
			c := &Conversation{db: d}
			rows := []*sdkws.MsgData{{Seq: 2, Status: constant.MsgStatusHasDeleted}, {Seq: 3, Status: constant.MsgStatusHasDeleted}}
			if tc.live {
				rows[1].Status = 0
			}
			cmd := common.Cmd2Value{Ctx: context.Background(), Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_group": {Msgs: rows}}}}
			err := c.doNotificationManager(cmd)
			if tc.live || tc.writeError {
				if err == nil || d.seq != 1 {
					t.Fatalf("must retain checkpoint on failure: err=%v seq=%d", err, d.seq)
				}
			} else if err != nil || d.seq != 3 {
				t.Fatalf("deleted page must commit: err=%v seq=%d", err, d.seq)
			}
		})
	}
}
