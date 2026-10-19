package conversation_msg

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type syncProfileLatencyDB struct {
	db_interface.DataBase
	members []*model_struct.LocalGroupMember
	err     error
	calls   int
}

func (d *syncProfileLatencyDB) GetGroupSomeMemberInfo(_ context.Context, _ string, ids []string) ([]*model_struct.LocalGroupMember, error) {
	d.calls++
	if len(ids) != 2 {
		panic("sender IDs must be deduplicated")
	}
	return d.members, d.err
}

func TestGroupMessageProfilesNeverRequireNetwork(t *testing.T) {
	for _, mode := range []string{"cached", "nickname-only", "missing", "failed"} {
		t.Run(mode, func(t *testing.T) {
			d := &syncProfileLatencyDB{}
			if mode == "cached" {
				d.members = []*model_struct.LocalGroupMember{{UserID: "a", Nickname: "local", FaceURL: "local-face"}}
			}
			if mode == "nickname-only" {
				d.members = []*model_struct.LocalGroupMember{{UserID: "a", Nickname: "local"}}
			}
			if mode == "failed" {
				d.err = errors.New("unavailable")
			}
			// No user/group service exists: attempting an HTTP fallback fails this test.
			c := &Conversation{db: d}
			rows := []*model_struct.LocalChatLog{{SendID: "a", SenderNickname: "wire", SenderFaceURL: "wire-face"}, {SendID: "a", SenderNickname: "wire", SenderFaceURL: "wire-face"}, {SendID: "b", SenderNickname: "wire-b", SenderFaceURL: "wire-b-face"}}
			c.groupHandle(context.Background(), rows[:1], rows[1:], &model_struct.LocalConversation{GroupID: "group"})
			expected := "wire"
			if mode == "cached" || mode == "nickname-only" {
				expected = "local"
			}
			if rows[0].SenderNickname != expected || rows[1].SenderNickname != expected || rows[2].SenderNickname != "wire-b" || d.calls != 1 {
				t.Fatalf("profile fallback changed message metadata: %+v", rows)
			}
		})
	}
}
