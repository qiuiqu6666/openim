package conversation_msg

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type profileSyncDB struct {
	db_interface.DataBase
	rows   []*model_struct.LocalConversation
	groups []*model_struct.LocalGroup
	writes int
	fail   bool
}

func (d *profileSyncDB) GetJoinedGroupListDB(context.Context) ([]*model_struct.LocalGroup, error) {
	return d.groups, nil
}
func (d *profileSyncDB) GetAllConversationListDB(context.Context) ([]*model_struct.LocalConversation, error) {
	return d.rows, nil
}
func (d *profileSyncDB) UpdateColumnsConversation(_ context.Context, id string, values map[string]interface{}) error {
	if d.fail {
		return errors.New("disk unavailable")
	}
	d.writes++
	for _, row := range d.rows {
		if row.ConversationID == id {
			row.ShowName = values["show_name"].(string)
			row.FaceURL = values["face_url"].(string)
		}
	}
	return nil
}

type profileSyncListener struct {
	open_im_sdk_callback.OnConversationListener
	batches [][]*model_struct.LocalConversation
}

func (l *profileSyncListener) OnConversationChanged(raw string) {
	var rows []*model_struct.LocalConversation
	if err := json.Unmarshal([]byte(raw), &rows); err != nil {
		panic(err)
	}
	l.batches = append(l.batches, rows)
}

func TestOfflineGroupProfileRepairsConversationAndPublishes(t *testing.T) {
	for _, face := range []string{"new-avatar", ""} {
		d := &profileSyncDB{groups: []*model_struct.LocalGroup{{GroupID: "group", GroupName: "Renamed offline", FaceURL: face}}, rows: []*model_struct.LocalConversation{
			{ConversationID: "sg_group", GroupID: "group", ConversationType: constant.ReadGroupChatType, ShowName: "Old", FaceURL: "old-avatar", DraftText: "draft", UnreadCount: 7},
			{ConversationID: "si_peer", ConversationType: constant.SingleChatType, ShowName: "Peer"},
		}}
		l := &profileSyncListener{}
		c := &Conversation{db: d, ConversationListener: func() open_im_sdk_callback.OnConversationListener { return l }}
		if err := c.reconcileGroupConversationProfiles(context.Background()); err != nil {
			t.Fatal(err)
		}
		row := d.rows[0]
		if row.ShowName != "Renamed offline" || row.FaceURL != face || row.UnreadCount != 7 || row.DraftText != "draft" || d.rows[1].ShowName != "Peer" {
			t.Fatalf("incorrect reconciliation: %+v", row)
		}
		if d.writes != 1 || len(l.batches) != 1 || l.batches[0][0].ShowName != row.ShowName {
			t.Fatal("missing list refresh")
		}
		if err := c.reconcileGroupConversationProfiles(context.Background()); err != nil {
			t.Fatal(err)
		}
		if d.writes != 1 || len(l.batches) != 1 {
			t.Fatal("unchanged sync must be a no-op")
		}
	}
}

func TestGroupProfileWriteFailureAndCancellationRemainRetryable(t *testing.T) {
	d := &profileSyncDB{fail: true, groups: []*model_struct.LocalGroup{{GroupID: "group", GroupName: "New"}}, rows: []*model_struct.LocalConversation{{ConversationID: "sg_group", GroupID: "group", ConversationType: constant.ReadGroupChatType, ShowName: "Old"}}}
	l := &profileSyncListener{}
	c := &Conversation{db: d, ConversationListener: func() open_im_sdk_callback.OnConversationListener { return l }}
	if err := c.reconcileGroupConversationProfiles(context.Background()); err == nil || len(l.batches) != 0 {
		t.Fatal("failed write acknowledged")
	}
	d.fail = false
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := c.reconcileGroupConversationProfiles(ctx); !errors.Is(err, context.Canceled) || d.writes != 0 {
		t.Fatal("cancelled session wrote profiles")
	}
	if err := c.reconcileGroupConversationProfiles(context.Background()); err != nil || d.writes != 1 {
		t.Fatalf("retry failed: %v", err)
	}
}
