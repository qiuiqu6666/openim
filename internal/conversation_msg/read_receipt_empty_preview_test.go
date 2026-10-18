package conversation_msg

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type emptyPreviewReceiptDB struct {
	*watermarkDB
	checkpoint int64
}

func (d *emptyPreviewReceiptDB) GetMessagesBySeqs(_ context.Context, _ string, seqs []int64) ([]*model_struct.LocalChatLog, error) {
	if d.queryErr != nil {
		return nil, d.queryErr
	}
	var rows []*model_struct.LocalChatLog
	for _, row := range d.rows {
		for _, seq := range seqs {
			if row.Seq == seq {
				copy := *row
				rows = append(rows, &copy)
				break
			}
		}
	}
	return rows, nil
}

func (d *emptyPreviewReceiptDB) SetNotificationSeq(_ context.Context, _ string, seq int64) error {
	d.checkpoint = seq
	return nil
}

func TestExplicitReceiptEmptyPreviewPage(t *testing.T) {
	for _, tc := range []struct {
		name, preview                                 string
		sparse, writeFailure, queryFailure, wantError bool
	}{
		{name: "empty preview"},
		{name: "empty preview replay with sparse cache", sparse: true},
		{name: "existing preview", preview: `{"clientMsgID":"own","seq":4}`},
		{name: "malformed preview remains retryable", preview: `{`, wantError: true},
		{name: "write failure remains retryable", writeFailure: true, wantError: true},
		{name: "query failure remains retryable", queryFailure: true, wantError: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, store, listener := watermarkFixture()
			store.conversation.LatestMsg = tc.preview
			if tc.sparse {
				store.rows = nil
			}
			if tc.writeFailure {
				store.writeErr = errors.New("storage write failure")
			}
			if tc.queryFailure {
				store.queryErr = errors.New("storage query failure")
			}
			d := &emptyPreviewReceiptDB{watermarkDB: store, checkpoint: 56}
			c.db = d
			tips := &sdkws.MarkAsReadTips{ConversationID: "chat", MarkAsReadUserID: "peer", Seqs: []int64{4, 500}}
			msg := &sdkws.MsgData{Seq: 57, ContentType: constant.HasReadReceipt, SendTime: 1234, Content: []byte(utils.StructToJsonString(sdk_struct.NotificationElem{Detail: utils.StructToJsonString(tips)}))}
			cmd := common.Cmd2Value{Ctx: context.Background(), Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_chat": {Msgs: []*sdkws.MsgData{msg}}}}}
			for attempt := 0; attempt < 2; attempt++ {
				err := c.doNotificationManager(cmd)
				if tc.wantError {
					if err == nil || d.checkpoint != 56 {
						t.Fatalf("failure acknowledged: err=%v checkpoint=%d", err, d.checkpoint)
					}
					continue
				}
				if err != nil || d.checkpoint != 57 {
					t.Fatalf("receipt page blocked: err=%v checkpoint=%d", err, d.checkpoint)
				}
				if !tc.sparse && !store.rows[3].IsRead {
					t.Fatal("cached message was not marked read")
				}
				if tc.preview == "" && store.conversation.LatestMsg != "" {
					t.Fatal("receipt fabricated a preview")
				}
			}
			if !tc.wantError && len(listener.receipts) != 2 {
				t.Fatal("read receipt callback missing")
			}
		})
	}
}
