package user

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type profileLookupDB struct {
	db_interface.DataBase
	friend       bool
	conversation *model_struct.LocalConversation
	queries      int
	friendErr    error
}

func (d *profileLookupDB) GetFriendInfoList(context.Context, []string) ([]*model_struct.LocalFriend, error) {
	if d.friendErr != nil {
		return nil, d.friendErr
	}
	if d.friend {
		return []*model_struct.LocalFriend{{FriendUserID: "other"}}, nil
	}
	return nil, nil
}
func (d *profileLookupDB) GetConversationByUserID(context.Context, string) (*model_struct.LocalConversation, error) {
	d.queries++
	return d.conversation, nil
}
func TestGetUsersInfoAvoidsUnnecessaryProfileUpdates(t *testing.T) {
	for _, tc := range []struct {
		name              string
		friend            bool
		conversation      *model_struct.LocalConversation
		queries, commands int
	}{
		{name: "friend", friend: true},
		{name: "missing", queries: 1},
		{name: "empty database result", conversation: &model_struct.LocalConversation{}, queries: 1},
		{name: "invalid type", conversation: &model_struct.LocalConversation{ConversationID: "si_other"}, queries: 1},
		{name: "unchanged", conversation: &model_struct.LocalConversation{ConversationID: "si_other", ConversationType: constant.SingleChatType, ShowName: "name", FaceURL: "avatar"}, queries: 1},
		{name: "changed single", conversation: &model_struct.LocalConversation{ConversationID: "si_other", ConversationType: constant.SingleChatType}, queries: 1, commands: 2},
		{name: "changed notification", conversation: &model_struct.LocalConversation{ConversationID: "sn_other", ConversationType: constant.NotificationChatType}, queries: 1, commands: 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := &profileLookupDB{friend: tc.friend, conversation: tc.conversation}
			ch := make(chan common.Cmd2Value, 4)
			u := NewUser(d, "self", ch)
			u.UserCache().Store("other", &model_struct.LocalUser{UserID: "other", Nickname: "name", FaceURL: "avatar"})
			got, err := u.GetUsersInfo(context.Background(), []string{"other"})
			if err != nil || len(got) != 1 || got[0].Nickname != "name" {
				t.Fatalf("profile lost: %v %v", got, err)
			}
			if d.queries != tc.queries || len(ch) != tc.commands {
				t.Fatalf("queries=%d commands=%d, want %d/%d", d.queries, len(ch), tc.queries, tc.commands)
			}
			if tc.commands > 0 {
				conv := (<-ch).Value.(common.UpdateConNode).Args.(common.SourceIDAndSessionType)
				msg := (<-ch).Value.(common.UpdateMessageNode).Args.(common.UpdateMessageInfo)
				if conv.SessionType != tc.conversation.ConversationType || msg.SessionType != conv.SessionType || conv.Nickname != "name" || msg.FaceURL != "avatar" {
					t.Fatalf("invalid update: %+v %+v", conv, msg)
				}
			}
		})
	}
}
func TestGetUsersInfoPreservesFriendLookupFailure(t *testing.T) {
	want := errors.New("database failure")
	d := &profileLookupDB{friendErr: want}
	u := NewUser(d, "self", make(chan common.Cmd2Value, 2))
	u.UserCache().Store("other", &model_struct.LocalUser{UserID: "other"})
	if _, err := u.GetUsersInfo(context.Background(), []string{"other"}); !errors.Is(err, want) || d.queries != 0 {
		t.Fatalf("error=%v queries=%d", err, d.queries)
	}
}
