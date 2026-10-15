package conversation_msg

import (
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
	"testing"
)

func TestWindowCoverageAndFixedWatermark(t *testing.T) {
	req := sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 50}
	read := &model_struct.MessageWindowRead{Conversation: &model_struct.LocalConversation{MaxSeq: 5003}}
	for seq := int64(4951); seq <= 5003; seq++ {
		read.Rows = append(read.Rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(seq), Seq: seq, SendTime: 10000 - seq, Status: constant.MsgStatusSendSuccess, ContentType: constant.Text, Content: `{"content":"test"}`, AttachedInfo: "{}"})
	}
	// The newest sequences need not be visible, but still count as covered.
	read.Rows[47].Status = constant.MsgStatusHasDeleted
	read.Rows[48].Status = constant.MsgStatusHasDeleted
	read.Rows[49].ContentType = constant.Typing
	p := buildMessageWindow(req, read, 5000, "remote", false)
	if !p.Window.Publishable || len(p.MessageList) != 47 || p.MessageList[46].Seq != 4997 || p.Window.TargetWatermark != 5000 {
		t.Fatalf("wrong fixed window: %+v", p)
	}
	if len(p.Window.Covered) != 1 || p.Window.Covered[0] != [2]int64{4951, 5000} {
		t.Fatal(p.Window)
	}
	for i, m := range p.MessageList {
		if m.Seq != 4951+int64(i) {
			t.Fatal("ordered by client time instead of seq")
		}
	}
	// Removing a body cannot leave a persisted completeness flag behind.
	read.Rows = append(read.Rows[:10], read.Rows[11:]...)
	p = buildMessageWindow(req, read, 5000, "local", false)
	if p.Window.Publishable || len(p.Window.Missing) != 1 || p.Window.Missing[0] != [2]int64{4961, 4961} {
		t.Fatal(p.Window)
	}
}

func TestWindowEmptyRequiresAuthoritativeEvidence(t *testing.T) {
	req := sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 40}
	read := &model_struct.MessageWindowRead{Conversation: &model_struct.LocalConversation{}}
	if buildMessageWindow(req, read, 0, "local", false).Window.Publishable {
		t.Fatal("local empty claimed server empty")
	}
	p := buildMessageWindow(req, read, 0, "remote", true)
	if !p.Window.Publishable || !p.Window.EmptyConfirmed {
		t.Fatal(p.Window)
	}
	read.Conversation.MinSeq = 51
	p = buildMessageWindow(req, read, 50, "remote", true)
	if !p.Window.Publishable || !p.Window.EmptyConfirmed {
		t.Fatal("permission-empty window rejected", p.Window)
	}
	read.Conversation.IsPrivateChat = true
	if buildMessageWindow(req, read, 50, "local", false).Window.Publishable {
		t.Fatal("private cache published")
	}
}

func TestInvisibleTailKeepsOlderHistoryReachable(t *testing.T) {
	read := &model_struct.MessageWindowRead{Conversation: &model_struct.LocalConversation{MaxSeq: 5000}}
	for seq := int64(4881); seq <= 5000; seq++ {
		read.Rows = append(read.Rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(seq), Seq: seq, SendTime: 1000, Status: constant.MsgStatusHasDeleted})
	}
	p := buildMessageWindow(sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 120}, read, 5000, "remote", false)
	if p.Window.EmptyConfirmed || p.IsEnd || !p.Window.Publishable {
		t.Fatal("hidden tail falsely ended history", p.Window)
	}
	if err := setInvisibleWindowCursor(p, read); err != nil {
		t.Fatal(err)
	}
	if !p.ScanLimited || p.ScanCursor.Seq != 4881 || p.ScanCursor.ConversationID != "chat" {
		t.Fatal(p.ScanCursor)
	}
}
