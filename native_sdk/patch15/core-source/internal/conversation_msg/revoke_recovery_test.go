package conversation_msg

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/internal/group"
	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

type revokeRecoveryDB struct {
	db_interface.DataBase
	message                          model_struct.LocalChatLog
	profileErr, previewErr, writeErr error
	conversationReads                int
}

func (d *revokeRecoveryDB) GetMessageBySeq(context.Context, string, int64) (*model_struct.LocalChatLog, error) {
	m := d.message
	return &m, nil
}
func (d *revokeRecoveryDB) GetConversation(context.Context, string) (*model_struct.LocalConversation, error) {
	d.conversationReads++
	if d.conversationReads > 1 && d.previewErr != nil {
		return nil, d.previewErr
	}
	return &model_struct.LocalConversation{ConversationID: "sg_group", GroupID: "group", LatestMsg: `{"seq":20}`}, nil
}
func (d *revokeRecoveryDB) GetVersionSync(context.Context, string, string) (*model_struct.LocalVersionSync, error) {
	return nil, d.profileErr
}
func (d *revokeRecoveryDB) UpdateMessageBySeq(_ context.Context, _ string, m *model_struct.LocalChatLog) error {
	if d.writeErr != nil {
		return d.writeErr
	}
	d.message.Content, d.message.ContentType = m.Content, m.ContentType
	return nil
}
func (d *revokeRecoveryDB) SearchAllMessageByContentType(context.Context, string, int) ([]*model_struct.LocalChatLog, error) {
	return nil, nil
}

type revokeRecoveryListener struct {
	open_im_sdk_callback.OnAdvancedMsgListener
	events []string
}

func (l *revokeRecoveryListener) OnNewRecvMessageRevoked(s string) { l.events = append(l.events, s) }

func TestGroupRevokeSurvivesUnavailableMemberProfile(t *testing.T) {
	for _, stage := range []string{"profile", "preview", "storage"} {
		t.Run(stage, func(t *testing.T) {
			d := &revokeRecoveryDB{
				message:    model_struct.LocalChatLog{ClientMsgID: "m10", Seq: 10, SendID: "sender", SenderNickname: "Sender", ContentType: constant.Text, Content: `{"content":"secret"}`},
				profileErr: errors.New("member metadata unavailable"),
			}
			if stage == "preview" {
				d.previewErr = errors.New("preview unavailable")
			}
			if stage == "storage" {
				d.writeErr = errors.New("disk full")
			}
			l := &revokeRecoveryListener{}
			c := &Conversation{db: d, group: group.NewGroup("receiver", d, nil), msgListener: func() open_im_sdk_callback.OnAdvancedMsgListener { return l }}
			err := c.revokeMessage(context.Background(), &sdkws.RevokeMsgTips{ConversationID: "sg_group", Seq: 10, RevokerUserID: "sender", SesstionType: constant.ReadGroupChatType})
			if stage == "storage" {
				if err == nil || len(l.events) != 0 || d.message.ContentType != constant.Text {
					t.Fatal("failed storage must remain retryable without success callback")
				}
				return
			}
			if stage == "profile" && err != nil {
				t.Fatalf("profile blocked accepted revoke: %v", err)
			}
			if stage == "preview" && err == nil {
				t.Fatal("preview failure must remain retryable")
			}
			if d.message.ContentType != constant.RevokeNotification || len(l.events) != 1 {
				t.Fatalf("receiver retained original message: type=%d events=%d err=%v", d.message.ContentType, len(l.events), err)
			}
			var notice sdk_struct.MessageRevoked
			if err := json.Unmarshal([]byte(l.events[0]), &notice); err != nil {
				t.Fatal(err)
			}
			if notice.ClientMsgID != "m10" || notice.RevokerID != "sender" {
				t.Fatalf("wrong event: %+v", notice)
			}
		})
	}
}
