package conversation_msg

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/cache"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
	"testing"
)

type emptyHistoryDB struct{ *recoveryDB }

func (d *emptyHistoryDB) UpdateConversation(_ context.Context, c *model_struct.LocalConversation) error {
	d.conversation = *c
	return nil
}

func TestEmptyFirstHistoryPagePullsKnownTail(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	c.messagePullForwardEndSeqMap = cache.NewConversationSeqContextCache()
	c.maxSeqRecorder.Set("chat", 1000)
	var rows []*model_struct.LocalChatLog
	result := &sdk.GetAdvancedHistoryMessageListCallback{}
	pull, seqs := c.checkEndBlock(cmd.Ctx, "chat", false, 0, 40, &rows, result)
	if !pull || len(seqs) != 40 || seqs[0] != 961 || seqs[39] != 1000 || result.IsEnd {
		t.Fatalf("empty first page stopped at local data: pull=%v seqs=%v result=%+v", pull, seqs, result)
	}
}

func TestHistoryUpperEndDoesNotMaskNewServerWatermark(t *testing.T) {
	c, d, _, cmd := recoveryConversation(t)
	c.db = &emptyHistoryDB{d}
	c.messagePullReverseEndSeqMap = cache.NewConversationSeqContextCache()
	c.setConversationMinSeq(cmd.Ctx, true, "chat", 10)
	c.maxSeqRecorder.Set("chat", 20)
	rows := []*model_struct.LocalChatLog{{ClientMsgID: "ten", Seq: 10, SendTime: 10}}
	result := &sdk.GetAdvancedHistoryMessageListCallback{}
	pull, seqs := c.checkEndBlock(cmd.Ctx, "chat", true, 0, 40, &rows, result)
	if !pull || len(seqs) != 10 || result.IsEnd || d.conversation.MaxSeq != 0 {
		t.Fatalf("history end became a sticky permission boundary: pull=%v seqs=%v max=%d", pull, seqs, d.conversation.MaxSeq)
	}
}

func TestEmptyUnknownOfflineHistoryIsNotComplete(t *testing.T) {
	c, _, _, cmd := recoveryConversation(t)
	c.maxSeqRecorder.Set("chat", 0)
	c.messagePullForwardEndSeqMap = cache.NewConversationSeqContextCache()
	var rows []*model_struct.LocalChatLog
	result := &sdk.GetAdvancedHistoryMessageListCallback{}
	pull, _ := c.checkEndBlock(cmd.Ctx, "chat", false, 0, 40, &rows, result)
	if pull || result.IsEnd || result.ErrCode == 0 {
		t.Fatalf("offline uncertainty reported as end: %+v", result)
	}
}

func TestTrimmedHistoryPageKeepsUnreturnedBoundaryReachable(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		var base, incoming []*model_struct.LocalChatLog
		for seq := int64(1); seq <= 50; seq++ {
			row := &model_struct.LocalChatLog{Seq: seq, SendTime: seq}
			if (!reverse && seq == 50) || (reverse && seq == 1) {
				base = append(base, row)
			} else {
				incoming = append(incoming, row)
			}
		}
		if !reverse {
			for left, right := 0, len(incoming)-1; left < right; left, right = left+1, right-1 {
				incoming[left], incoming[right] = incoming[right], incoming[left]
			}
		}
		rows := mergeSortedArrays(base, incoming, 40, !reverse)
		end := int64(1)
		if reverse {
			end = 50
		}
		if len(rows) != 40 || historyPageReachedEnd(rows, reverse, end) {
			t.Fatalf("trimmed page ended early: reverse=%v rows=%v", reverse, rows)
		}
		// Returning the remaining rows can report the actual endpoint.
		if !historyPageReachedEnd(incoming, reverse, end) {
			t.Fatalf("visible endpoint not recognized: reverse=%v", reverse)
		}
	}
}
