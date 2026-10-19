//go:build cgo && !js

package conversation_msg

import (
	"context"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

// Legacy SDKs persisted multiple hidden rows for one server sequence. Reopen
// that database and exercise the real SQLite -> window path, without cleanup.
func TestWindowLegacyDuplicatesDoNotConsumeSequenceBudget(t *testing.T) {
	for _, missing := range []bool{false, true} {
		t.Run(fmt.Sprintf("missing=%t", missing), func(t *testing.T) {
			ctx := context.Background()
			dir := t.TempDir()
			d, err := db.NewDataBase(ctx, "self", dir, 0)
			if err != nil {
				t.Fatal(err)
			}
			if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", MaxSeq: 78}}); err != nil {
				t.Fatal(err)
			}
			var rows []*model_struct.LocalChatLog
			for seq := int64(39); seq <= 78; seq++ {
				if missing && seq == 60 {
					continue
				}
				row := &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(seq), Seq: seq, SendTime: 1000 + seq, Status: constant.MsgStatusSendSuccess, ContentType: constant.Text, Content: `{"content":"test"}`, AttachedInfo: "{}"}
				if seq <= 51 {
					row.Status = constant.MsgStatusHasDeleted
					row.Content = ""
				}
				rows = append(rows, row)
			}
			for n := 0; n < 50; n++ {
				rows = append(rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprintf("legacy-51-%d", n), Seq: 51, SendTime: 1051, Status: constant.MsgStatusHasDeleted})
			}
			if err = d.BatchInsertMessageList(ctx, "chat", rows); err != nil {
				t.Fatal(err)
			}
			if err = d.Close(ctx); err != nil {
				t.Fatal(err)
			}
			d, err = db.NewDataBase(ctx, "self", dir, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer d.Close(ctx)
			c := &Conversation{db: d}
			for _, target := range []int64{0, 78, 77} {
				p, err := c.messageWindow(ctx, sdk.GetAdvancedHistoryMessageListParams{ConversationID: "chat", Count: 40, TargetWatermark: target, LocalSnapshot: true, Window: true})
				if err != nil {
					t.Fatal(err)
				}
				// target 77 also needs seq 38, which this fixture intentionally lacks.
				wantReady := !missing && target != 77
				if p.Window.Publishable != wantReady {
					t.Fatalf("target=%d unexpected coverage: %+v", target, p.Window)
				}
				if wantReady && (len(p.MessageList) != 27 || p.Window.LowerBound != 39 || p.Window.TargetWatermark != 78) {
					t.Fatalf("lost visible rows: %+v", p)
				}
				if missing {
					found := false
					for _, gap := range p.Window.Missing {
						if gap[0] <= 60 && gap[1] >= 60 {
							found = true
						}
					}
					if !found {
						t.Fatal("real missing seq 60 was concealed")
					}
				}
				for _, m := range p.MessageList {
					if m.Seq <= 51 || (target > 0 && m.Seq > target) {
						t.Fatalf("hidden or future row exposed: %+v", m)
					}
				}
			}
			stored, err := d.ReadMessageWindow(ctx, "chat", 40, 78)
			if err != nil {
				t.Fatal(err)
			}
			duplicates := 0
			for _, row := range stored.Rows {
				if row.Seq == 51 {
					duplicates++
				}
			}
			if duplicates != 51 {
				t.Fatalf("window read mutated or dropped legacy rows: %d", duplicates)
			}
		})
	}
}
