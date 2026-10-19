package conversation_msg

import (
	"context"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/internal/group"
	"github.com/openimsdk/openim-sdk-core/v3/internal/user"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
)

type missingProfileDB struct {
	db_interface.DataBase
	conversation model_struct.LocalConversation
	profile      *model_struct.LocalUser
	lookups      int
}

func (d *missingProfileDB) GetConversation(context.Context, string) (*model_struct.LocalConversation, error) {
	return &d.conversation, nil
}

func (d *missingProfileDB) GetLoginUser(context.Context, string) (*model_struct.LocalUser, error) {
	d.lookups++
	if d.profile == nil {
		return nil, errs.ErrRecordNotFound.Wrap()
	}
	return d.profile, nil
}

func TestMessageProfileMissingDoesNotSuppressPeerOrGroupProfiles(t *testing.T) {
	for _, session := range []int32{constant.SingleChatType, constant.ReadGroupChatType} {
		t.Run(map[int32]string{constant.SingleChatType: "single", constant.ReadGroupChatType: "group"}[session], func(t *testing.T) {
			d := &missingProfileDB{conversation: model_struct.LocalConversation{ConversationID: "chat", ConversationType: session, ShowName: "peer name", FaceURL: "peer face"}}
			u := user.NewUser(d, "self", nil)
			u.UserCache().BatchAddSpecialUser(map[string]*model_struct.LocalUser{"peer": {UserID: "peer", Nickname: "peer name", FaceURL: "peer face"}})
			c := &Conversation{db: d, loginUserID: "self", user: u, group: group.NewGroup("self", d, nil)}
			for i := 0; i < 100; i++ {
				row := &model_struct.LocalChatLog{ClientMsgID: "message", SendID: "peer", SenderNickname: "wire name", Seq: 12, IsRead: true}
				got := c.faceURLAndNicknameHandle(context.Background(), nil, []*model_struct.LocalChatLog{row}, "chat")
				if len(got) != 1 || got[0] != row || row.SenderNickname != "peer name" || row.SenderFaceURL != "peer face" || !row.IsRead || row.Seq != 12 {
					t.Fatalf("message/profile changed incorrectly: %+v", row)
				}
			}
			if d.lookups != 0 {
				t.Fatalf("peer/group messages performed %d unnecessary self-profile lookups", d.lookups)
			}
		})
	}
}

func TestMessageProfileMissingPreservesSelfAndUsesRecoveredProfile(t *testing.T) {
	d := &missingProfileDB{conversation: model_struct.LocalConversation{ConversationID: "chat", ConversationType: constant.SingleChatType, ShowName: "peer name"}}
	c := &Conversation{db: d, loginUserID: "self"}
	self := &model_struct.LocalChatLog{SendID: "self", SenderNickname: "wire self", SenderFaceURL: "wire face", Seq: 7, IsRead: true}
	peer := &model_struct.LocalChatLog{SendID: "peer", SenderNickname: "wire peer", Seq: 8}
	for i := 0; i < 100; i++ {
		got := c.faceURLAndNicknameHandle(context.Background(), []*model_struct.LocalChatLog{self}, []*model_struct.LocalChatLog{peer}, "chat")
		if len(got) != 2 || self.SenderNickname != "wire self" || self.SenderFaceURL != "wire face" || peer.SenderNickname != "peer name" || !self.IsRead || peer.IsRead {
			t.Fatalf("missing profile corrupted message metadata: self=%+v peer=%+v", self, peer)
		}
	}
	d.profile = &model_struct.LocalUser{UserID: "self", Nickname: "recovered", FaceURL: "recovered face"}
	c.faceURLAndNicknameHandle(context.Background(), []*model_struct.LocalChatLog{self}, nil, "chat")
	if self.SenderNickname != "recovered" || self.SenderFaceURL != "recovered face" || self.Seq != 7 || !self.IsRead {
		t.Fatalf("recovered profile not applied safely: %+v", self)
	}
}
