package conversation_msg

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
)

type receiptConversationListener struct {
	open_im_sdk_callback.OnConversationListener
}

func (*receiptConversationListener) OnConversationChanged(string)           {}
func (*receiptConversationListener) OnTotalUnreadMessageCountChanged(int32) {}
func (d *watermarkDB) GetMultipleConversationDB(context.Context, []string) ([]*model_struct.LocalConversation, error) {
	return nil, nil
}
func (d *watermarkDB) GetTotalUnreadMsgCountDB(context.Context) (int32, error) {
	return d.conversation.UnreadCount, nil
}
func (d *watermarkDB) MarkConversationMessageAsReadBySeqs(_ context.Context, _ string, seqs []int64) (int64, error) {
	if d.writeErr != nil {
		return 0, d.writeErr
	}
	var changed int64
	for _, row := range d.rows {
		for _, seq := range seqs {
			if row.Seq == seq && row.SendID != "self" && !row.IsRead {
				row.IsRead = true
				changed++
			}
		}
	}
	return changed, nil
}

func TestRevokeIgnoresDeletedQuoteBodies(t *testing.T) {
	c := &Conversation{}
	for _, status := range []int32{constant.MsgStatusHasDeleted, constant.MsgStatusFiltered} {
		row := &model_struct.LocalChatLog{ClientMsgID: "[SEQ_DUP]old", Seq: 23193, ContentType: constant.Quote, Status: status}
		if err := c.quoteMsgRevokeHandle(context.Background(), "sg_group", row, sdk_struct.MessageRevoked{}); err != nil {
			t.Fatalf("deleted quote blocked revoke: %v", err)
		}
	}
	if err := c.quoteMsgRevokeHandle(context.Background(), "sg_group", &model_struct.LocalChatLog{Status: constant.MsgStatusSendSuccess}, sdk_struct.MessageRevoked{}); err == nil {
		t.Fatal("an invalid live quote must remain distinguishable from a tombstone")
	}
}

type explicitReceiptDB struct {
	*watermarkDB
	updates int
	failure error
}

func (d *explicitReceiptDB) MarkConversationMessageAsReadBySeqs(context.Context, string, []int64) (int64, error) {
	d.updates++
	return 0, d.failure
}

func TestExplicitSelfReceiptReconcilesMissingAndAlreadyReadRows(t *testing.T) {
	for _, lastRead := range []bool{false, true} {
		c, original, _ := watermarkFixture()
		d := &explicitReceiptDB{watermarkDB: original}
		c.db = d
		if lastRead {
			original.rows[1].IsRead = true
		}
		seq := int64(3999) // Outside the bounded local cache, as in the heat log.
		if lastRead {
			seq = 1
		}
		for n := 0; n < 2; n++ {
			if err := c.doUnreadCount(context.Background(), &original.conversation, seq, []int64{1, 3995, 3999}); err != nil {
				t.Fatal(err)
			}
		}
		if d.updates != 2 {
			t.Fatal("a cached read tail bypassed other receipt sequences")
		}
	}
}

func TestExplicitSelfReceiptPreservesStorageError(t *testing.T) {
	c, original, _ := watermarkFixture()
	failure := errors.New("database unavailable")
	c.db = &explicitReceiptDB{watermarkDB: original, failure: failure}
	if err := c.doUnreadCount(context.Background(), &original.conversation, 1, []int64{1}); !errors.Is(err, failure) {
		t.Fatalf("lost storage failure: %v", err)
	}
}

func TestExplicitSelfReceiptWithNoLocalSequenceOrPreview(t *testing.T) {
	c, original, _ := watermarkFixture()
	d := &explicitReceiptDB{watermarkDB: original}
	c.db = d
	c.maxSeqRecorder = NewMaxSeqRecorder()
	original.conversation.LatestMsg = ""
	if err := c.doUnreadCount(context.Background(), &original.conversation, 3999, []int64{3995, 3999}); err != nil {
		t.Fatal(err)
	}
	if original.conversation.UnreadCount != 3 || d.updates != 1 {
		t.Fatal("missing sequence metadata changed the unread count")
	}
}
