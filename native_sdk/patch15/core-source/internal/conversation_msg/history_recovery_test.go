package conversation_msg

import (
	"context"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/internal/interaction"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/cache"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

type historyRecoveryDB struct {
	*recoveryDB
	lookupErr error
}

func (d *historyRecoveryDB) GetMessagesByClientMsgIDs(context.Context, string, []string) ([]*model_struct.LocalChatLog, error) {
	return nil, d.lookupErr
}

func (d *historyRecoveryDB) GetMessageList(context.Context, string, int, int64, int64, string, bool) ([]*model_struct.LocalChatLog, error) {
	return []*model_struct.LocalChatLog{{ClientMsgID: "m133", Seq: 133, SendTime: 133}}, nil
}

func TestFailedGapFillDoesNotAdvanceHistoryCursor(t *testing.T) {
	ctx := ccontext.WithInfo(context.Background(), &ccontext.GlobalConfig{UserID: "self"})
	ctx, cancel := context.WithCancel(ctx)
	cancel()
	c := &Conversation{LongConnMgr: interaction.NewLongConnMgr(ctx, nil, nil, nil, nil),
		db: &historyRecoveryDB{recoveryDB: &recoveryDB{}}, loginUserID: "self",
		messagePullForwardEndSeqMap: cache.NewConversationSeqContextCache(), messagePullReverseEndSeqMap: cache.NewConversationSeqContextCache()}
	c.messagePullReverseEndSeqMap.Store("chat", 0, 32)
	result := &sdk.GetAdvancedHistoryMessageListCallback{}
	rows, err := c.fetchMessagesWithGapCheck(ctx, "chat", 40, 32, 32, "m32", true, 0, result)
	if err == nil || len(rows) != 0 {
		t.Fatal("failed range was returned as a successful page")
	}
	if seq, _ := c.messagePullReverseEndSeqMap.Load("chat", 0); seq != 32 {
		t.Fatalf("advanced over missing range: %d", seq)
	}
}

func TestHistoryRetryUsesRequestedAnchorNotPreviousPage(t *testing.T) {
	c := &Conversation{messagePullForwardEndSeqMap: cache.NewConversationSeqContextCache(), messagePullReverseEndSeqMap: cache.NewConversationSeqContextCache()}
	for _, reverse := range []bool{false, true} {
		c.messagePullForwardEndSeqMap.Store("chat", 0, 133)
		c.messagePullReverseEndSeqMap.Store("chat", 0, 133)
		if err := c.handleEndSeq(context.Background(), sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat"}, reverse, &model_struct.LocalChatLog{Seq: 32}); err != nil {
			t.Fatal(err)
		}
		m := c.messagePullForwardEndSeqMap
		if reverse {
			m = c.messagePullReverseEndSeqMap
		}
		if seq, _ := m.Load("chat", 0); seq != 32 {
			t.Fatalf("retry skipped 33..132: %d", seq)
		}
	}
}

func TestHistoryStorageFailureIsNotReportedAsComplete(t *testing.T) {
	for _, stage := range []string{"lookup", "insert"} {
		t.Run(stage, func(t *testing.T) {
			want := errors.New("storage unavailable")
			d := &historyRecoveryDB{recoveryDB: &recoveryDB{}}
			if stage == "lookup" {
				d.lookupErr = want
			} else {
				d.writeErr = want
			}
			c := &Conversation{db: d, loginUserID: "self"}
			var rows []*model_struct.LocalChatLog
			err := c.pullMessageIntoTable(context.Background(), "chat", []*model_struct.LocalChatLog{{ClientMsgID: "m33", Seq: 33, SendID: "other"}}, &rows)
			if !errors.Is(err, want) {
				t.Fatalf("lost %s failure: %v", stage, err)
			}
		})
	}
}
