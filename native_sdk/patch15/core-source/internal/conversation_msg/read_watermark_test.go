package conversation_msg

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type watermarkDB struct {
	db_interface.DataBase
	rows               []*model_struct.LocalChatLog
	conversation       model_struct.LocalConversation
	queryErr, writeErr error
	queries            int
}

func (d *watermarkDB) GetMessageBySeq(_ context.Context, _ string, seq int64) (*model_struct.LocalChatLog, error) {
	for _, row := range d.rows {
		if row.Seq == seq {
			return row, nil
		}
	}
	return nil, errors.New("missing message")
}

func TestReadWatermarkExplicitSelfReplayDoesNotFailPage(t *testing.T) {
	c, d, _ := watermarkFixture()
	d.rows[1].IsRead = true
	tips := &sdkws.MarkAsReadTips{ConversationID: "chat", MarkAsReadUserID: "self", HasReadSeq: 1, Seqs: []int64{1}}
	msg := &sdkws.MsgData{Content: []byte(utils.StructToJsonString(sdk_struct.NotificationElem{Detail: utils.StructToJsonString(tips)}))}
	if err := c.doReadDrawing(context.Background(), msg); err != nil {
		t.Fatal(err)
	}
}

func (d *watermarkDB) GetConversation(context.Context, string) (*model_struct.LocalConversation, error) {
	v := d.conversation
	return &v, nil
}
func (d *watermarkDB) GetReadWatermarkMessages(_ context.Context, _ string, after, through int64) ([]*model_struct.LocalChatLog, error) {
	d.queries++
	if d.queryErr != nil {
		return nil, d.queryErr
	}
	var result []*model_struct.LocalChatLog
	for _, row := range d.rows {
		if row.Seq > after && row.Seq <= through {
			v := *row
			result = append(result, &v)
			if len(result) == 2 {
				break
			}
		}
	}
	return result, nil
}
func (d *watermarkDB) UpdateMessage(_ context.Context, _ string, row *model_struct.LocalChatLog) error {
	if d.writeErr != nil {
		return d.writeErr
	}
	for _, old := range d.rows {
		if old.ClientMsgID == row.ClientMsgID {
			*old = *row
		}
	}
	return nil
}
func (d *watermarkDB) UpdateColumnsConversation(_ context.Context, _ string, columns map[string]interface{}) error {
	if d.writeErr != nil {
		return d.writeErr
	}
	if v, ok := columns["latest_msg"].(string); ok {
		d.conversation.LatestMsg = v
	}
	if v, ok := columns["unread_count"].(int64); ok {
		d.conversation.UnreadCount = int32(v)
	}
	return nil
}

type watermarkListener struct {
	open_im_sdk_callback.OnAdvancedMsgListener
	receipts []string
}

func (l *watermarkListener) OnRecvC2CReadReceipt(s string) { l.receipts = append(l.receipts, s) }
func watermarkFixture() (*Conversation, *watermarkDB, *watermarkListener) {
	d := &watermarkDB{conversation: model_struct.LocalConversation{ConversationID: "chat", ConversationType: constant.SingleChatType, UnreadCount: 3, LatestMsg: `{"clientMsgID":"own","sendID":"self","seq":4}`}, rows: []*model_struct.LocalChatLog{
		{ClientMsgID: "pending", Seq: 0, SendID: "self"}, {ClientMsgID: "peer", Seq: 1, SendID: "peer"}, {ClientMsgID: "own2", Seq: 2, SendID: "self"}, {ClientMsgID: "own", Seq: 4, SendID: "self"}, {ClientMsgID: "later", Seq: 9, SendID: "self"},
	}}
	l := &watermarkListener{}
	c := &Conversation{db: d, loginUserID: "self", maxSeqRecorder: NewMaxSeqRecorder(), conversationEventQueue: make(chan common.Cmd2Value, 20), msgListener: func() open_im_sdk_callback.OnAdvancedMsgListener { return l }, ConversationListener: func() open_im_sdk_callback.OnConversationListener { return &receiptConversationListener{} }}
	c.maxSeqRecorder.Set("chat", 9)
	return c, d, l
}
func watermarkNotice(user string, seq int64) *sdkws.MsgData {
	tips := &sdkws.MarkAsReadTips{ConversationID: "chat", MarkAsReadUserID: user, HasReadSeq: seq}
	return &sdkws.MsgData{SendTime: 1234, Content: []byte(utils.StructToJsonString(sdk_struct.NotificationElem{Detail: utils.StructToJsonString(tips)}))}
}
func TestReadWatermarkPeerRangeAndReplay(t *testing.T) {
	c, d, l := watermarkFixture()
	for i := 0; i < 2; i++ {
		if err := c.doReadDrawing(context.Background(), watermarkNotice("peer", 4)); err != nil {
			t.Fatal(err)
		}
	}
	if d.rows[0].IsRead || d.rows[1].IsRead || !d.rows[2].IsRead || !d.rows[3].IsRead || d.rows[4].IsRead {
		t.Fatal("wrong sender/range marked")
	}
	if len(l.receipts) != 4 || d.queries != 6 {
		t.Fatalf("missing paged receipts: %d, queries=%d", len(l.receipts), d.queries)
	}
	var latest sdk_struct.MsgStruct
	_ = utils.JsonStringToStruct(d.conversation.LatestMsg, &latest)
	if !latest.IsRead || d.conversation.UnreadCount != 3 {
		t.Fatal("preview or own unread corrupted")
	}
}
func TestReadWatermarkSelfAndStale(t *testing.T) {
	c, d, l := watermarkFixture()
	for _, seq := range []int64{8, 2} {
		if err := c.doReadDrawing(context.Background(), watermarkNotice("self", seq)); err != nil {
			t.Fatal(err)
		}
	}
	if !d.rows[1].IsRead || d.rows[2].IsRead || d.conversation.UnreadCount != 1 || len(l.receipts) != 0 {
		t.Fatal("self receipt incorrectly changes peer reads/unread")
	}
}
func TestReadWatermarkEmptyAndHuge(t *testing.T) {
	c, d, _ := watermarkFixture()
	d.rows = nil
	for _, seq := range []int64{0, -1, 1 << 60} {
		if err := c.doReadDrawing(context.Background(), watermarkNotice("peer", seq)); err != nil {
			t.Fatal(err)
		}
	}
	if d.queries != 1 {
		t.Fatal("expanded watermark or queried invalid range")
	}
}
func TestReadWatermarkStorageFailuresRemainRetryable(t *testing.T) {
	for _, stage := range []string{"query", "write"} {
		t.Run(stage, func(t *testing.T) {
			c, d, _ := watermarkFixture()
			failure := errors.New("storage unavailable")
			if stage == "query" {
				d.queryErr = failure
			} else {
				d.writeErr = failure
			}
			if err := c.doReadDrawing(context.Background(), watermarkNotice("peer", 4)); !errors.Is(err, failure) {
				t.Fatalf("lost failure: %v", err)
			}
			d.queryErr = nil
			d.writeErr = nil
			if err := c.doReadDrawing(context.Background(), watermarkNotice("peer", 4)); err != nil {
				t.Fatal(err)
			}
		})
	}
}
