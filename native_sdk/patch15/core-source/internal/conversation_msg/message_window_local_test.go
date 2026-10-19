package conversation_msg

import (
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

func TestWindowIncludesLocalCallWithoutClaimingCoverage(t *testing.T) {
	req := sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 2}
	row := func(id string, seq, time int64) *model_struct.LocalChatLog {
		return &model_struct.LocalChatLog{ClientMsgID: id, Seq: seq, SendTime: time, Status: constant.MsgStatusSendSuccess, ContentType: constant.Custom, Content: `{"data":"call"}`, AttachedInfo: "{}"}
	}
	read := &model_struct.MessageWindowRead{Conversation: &model_struct.LocalConversation{MaxSeq: 2}, Rows: []*model_struct.LocalChatLog{
		row("first", 1, 100), row("last", 2, 300), row("call", 0, 200), row("old", 0, 90), row("deleted", 0, 400), row("private", 0, 500),
	}}
	read.Rows[4].Status = constant.MsgStatusHasDeleted
	read.Rows[5].AttachedInfo = `{"isPrivateChat":true}`
	p := buildMessageWindow(req, read, 2, "local", false)
	if !p.Window.Publishable || len(p.MessageList) != 3 || p.MessageList[1].ClientMsgID != "call" || len(p.Window.Covered) != 1 || p.Window.Covered[0] != [2]int64{1, 2} {
		t.Fatalf("local call missing or coverage changed: %+v, %+v", p.MessageList, p.Window)
	}
	read.Rows = read.Rows[1:]
	p = buildMessageWindow(req, read, 2, "local", false)
	if p.Window.Publishable || len(p.Window.Missing) != 1 {
		t.Fatal("local record covered a missing server sequence")
	}
	p = buildMessageWindow(req, read, 0, "remote", true)
	for _, m := range p.MessageList {
		if m.Seq == 0 {
			t.Fatal("local record crossed empty permission boundary")
		}
	}
}
