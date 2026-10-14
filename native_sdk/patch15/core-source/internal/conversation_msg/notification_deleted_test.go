package conversation_msg

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type notificationCheckpointDB struct {
	db_interface.DataBase
	seq int64
	err error
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
