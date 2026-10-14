package conversation_msg

import (
	"encoding/json"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"testing"
)

type deliveryStateListener struct {
	*recoveryCallbacks
	messages []sdk_struct.MsgStruct
}

func (l *deliveryStateListener) OnRecvNewMessage(s string) {
	var msg sdk_struct.MsgStruct
	_ = json.Unmarshal([]byte(s), &msg)
	l.messages = append(l.messages, msg)
}

func TestPendingDeliveryPreservesLocalRecallAndReadState(t *testing.T) {
	for _, self := range []bool{false, true} {
		name := "peer"
		if self {
			name = "self"
		}
		t.Run(name, func(t *testing.T) {
			c, d, callbacks, cmd := selfMessageLossFixture(t)
			listener := &deliveryStateListener{recoveryCallbacks: callbacks}
			c.msgListener = func() open_im_sdk_callback.OnAdvancedMsgListener { return listener }
			p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
			if !self {
				p.Msgs["chat"].Msgs[0].SendID = "other"
				p.Msgs["chat"].Msgs[0].RecvID = "self"
			}
			p.Recovery = true
			cmd.Value = p
			d.conversationErr = errors.New("failure after message commit")
			if err := c.doMsgNew(cmd); err == nil {
				t.Fatal("expected partial failure")
			}
			d.rows["m6"].ContentType = constant.RevokeNotification
			d.rows["m6"].Content = `{"detail":"revoked"}`
			d.rows["m6"].IsRead = true
			d.rows["m6"].LocalEx = "local-state"
			c.pendingSelfDeliveries = nil
			d.conversationErr = nil
			if err := c.doMsgNew(cmd); err != nil {
				t.Fatal(err)
			}
			if len(listener.messages) != 1 {
				t.Fatalf("pending delivery lost: %v", listener.messages)
			}
			row := listener.messages[0]
			if row.ContentType != constant.RevokeNotification || !row.IsRead || row.LocalEx != "local-state" {
				t.Fatalf("stale payload replayed: %+v", row)
			}
		})
	}
}
