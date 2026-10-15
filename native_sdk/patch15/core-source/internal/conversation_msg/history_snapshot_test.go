package conversation_msg

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/cache"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

type snapshotDB struct {
	*recoveryDB
	rows  []*model_struct.LocalChatLog
	err   error
	count int
}

func (d *snapshotDB) GetMessageList(_ context.Context, _ string, count int, _, _ int64, _ string, _ bool) ([]*model_struct.LocalChatLog, error) {
	d.count = count
	return d.rows, d.err
}

func TestLocalSnapshotNeedsNoConnectionAndNeverAdvancesHistory(t *testing.T) {
	d := &snapshotDB{recoveryDB: &recoveryDB{conversation: model_struct.LocalConversation{MinSeq: 2}}}
	for i, id := range []string{"below-min", "deleted", "private", "typing", "old", "new"} {
		d.rows = append(d.rows, &model_struct.LocalChatLog{ClientMsgID: id, Seq: int64(i + 1), SendTime: time.Now().UnixMilli() + int64(i), ContentType: constant.Text, Content: `{"content":"test"}`, Status: constant.MsgStatusSendSuccess})
	}
	d.rows[1].Status = constant.MsgStatusHasDeleted
	d.rows[2].AttachedInfo = `{"isPrivateChat":true,"burnDuration":999999999}`
	d.rows[3].ContentType = constant.Typing
	c := &Conversation{db: d, messagePullForwardEndSeqMap: cache.NewConversationSeqContextCache(), messagePullReverseEndSeqMap: cache.NewConversationSeqContextCache()}
	c.messagePullForwardEndSeqMap.Store("chat", 0, 42)
	// No connection manager is installed: any network path would panic.
	started := time.Now()
	page, err := c.getAdvancedHistoryMessageList(context.Background(), sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 40, LocalSnapshot: true}, false)
	if err != nil || !page.LocalSnapshot || page.IsEnd || page.ScanCursor != nil || len(page.MessageList) != 2 {
		t.Fatalf("invalid snapshot: %+v, %v", page, err)
	}
	if page.MessageList[0].ClientMsgID != "old" || page.MessageList[1].ClientMsgID != "new" {
		t.Fatal("snapshot order")
	}
	if seq, _ := c.messagePullForwardEndSeqMap.Load("chat", 0); seq != 42 {
		t.Fatal("snapshot changed paging")
	}
	t.Logf("local first page without network: %s", time.Since(started))
	d.err = errors.New("database unavailable")
	if _, err := c.getAdvancedHistoryMessageList(context.Background(), sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 40, LocalSnapshot: true}, false); !errors.Is(err, d.err) {
		t.Fatal("database error swallowed")
	}
}

func TestLocalSnapshotRejectsPagingAndPrivateConversations(t *testing.T) {
	d := &snapshotDB{recoveryDB: &recoveryDB{conversation: model_struct.LocalConversation{IsPrivateChat: true}}}
	c := &Conversation{db: d}
	req := sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 1000, LocalSnapshot: true}
	page, err := c.getAdvancedHistoryMessageList(context.Background(), req, false)
	if err != nil || len(page.MessageList) != 0 || d.count != 0 {
		t.Fatal("read private snapshot")
	}
	d.conversation.IsPrivateChat = false
	if _, err := c.getAdvancedHistoryMessageList(context.Background(), req, false); err != nil || d.count != 100 {
		t.Fatal("unbounded query")
	}
	req.StartClientMsgID = "anchor"
	if _, err := c.getAdvancedHistoryMessageList(context.Background(), req, false); err == nil {
		t.Fatal("accepted paging")
	}
	req.StartClientMsgID = ""
	if _, err := c.getAdvancedHistoryMessageList(context.Background(), req, true); err == nil {
		t.Fatal("accepted reverse")
	}
}

func TestLocalSnapshotAttestsLatestWindowIncludingDeletedRows(t *testing.T) {
	for _, scenario := range []struct {
		name  string
		seqs  []int64
		max   int64
		ready bool
	}{
		{"complete", []int64{1, 2, 3}, 3, true},
		{"middle gap despite latest preview", []int64{1, 3}, 3, false},
		{"stale full page", []int64{1, 2, 3}, 4, false},
		{"bounded latest range", []int64{98, 99, 100}, 100, true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			d := &snapshotDB{recoveryDB: &recoveryDB{conversation: model_struct.LocalConversation{MaxSeq: scenario.max}}}
			for _, seq := range scenario.seqs {
				d.rows = append(d.rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(seq), Seq: seq, SendTime: 1000, ContentType: constant.Text, Content: `{"content":"test"}`, Status: constant.MsgStatusSendSuccess})
			}
			if len(d.rows) > 1 {
				d.rows[1].Status = constant.MsgStatusHasDeleted
			}
			c := &Conversation{db: d}
			page, err := c.getAdvancedHistoryMessageList(context.Background(), sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 3, LocalSnapshot: true}, false)
			if err != nil || page.SnapshotReady != scenario.ready {
				t.Fatalf("readiness=%v err=%v", page.SnapshotReady, err)
			}
			for i := 1; i < len(page.MessageList); i++ {
				if page.MessageList[i-1].Seq >= page.MessageList[i].Seq {
					t.Fatal("same timestamp messages reordered")
				}
			}
		})
	}
}
