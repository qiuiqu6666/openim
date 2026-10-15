//go:build cgo && !js

package db

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"gorm.io/gorm"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// This helper is a separate OS process. The parent kills it after SQLite has
// written a transaction page, or after commit but before an SDK/UI receipt.
func TestWindowCrashChild(t *testing.T) {
	dir := os.Getenv("CHAT_WINDOW_CRASH_DIR")
	if dir == "" {
		t.Skip("subprocess only")
	}
	ctx := context.Background()
	d, err := NewDataBase(ctx, "window-crash", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	phase := os.Getenv("CHAT_WINDOW_CRASH_PHASE")
	pause := func() {
		if err := os.WriteFile(filepath.Join(dir, "ready"), []byte(phase), 0600); err != nil {
			t.Fatal(err)
		}
		for {
			time.Sleep(time.Second)
		}
	}
	if phase == "during" {
		if err = d.conn.Callback().Create().After("gorm:create").Register("window_crash", func(tx *gorm.DB) {
			if tx.Statement.Table == utils.GetTableName("chat") {
				pause()
			}
		}); err != nil {
			t.Fatal(err)
		}
	}
	err = d.CommitMessageSyncBatch(ctx, nil, map[string][]*model_struct.LocalChatLog{"chat": {{ClientMsgID: "m2", Seq: 2}}}, []*model_struct.LocalConversation{{ConversationID: "chat", MaxSeq: 2, UnreadCount: 2}}, nil)
	if err != nil {
		t.Fatal(err)
	}
	pause()
}

func TestWindowCrashRecovery(t *testing.T) {
	for _, phase := range []string{"during", "after"} {
		t.Run(phase, func(t *testing.T) {
			dir := t.TempDir()
			ctx := context.Background()
			d, err := NewDataBase(ctx, "window-crash", dir, 0)
			if err != nil {
				t.Fatal(err)
			}
			if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", MaxSeq: 1, UnreadCount: 1}}); err != nil {
				t.Fatal(err)
			}
			if err = d.BatchInsertMessageList(ctx, "chat", []*model_struct.LocalChatLog{{ClientMsgID: "m1", Seq: 1}}); err != nil {
				t.Fatal(err)
			}
			if err = d.Close(ctx); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command(os.Args[0], "-test.run=^TestWindowCrashChild$", "-test.timeout=30s")
			cmd.Env = append(os.Environ(), "CHAT_WINDOW_CRASH_DIR="+dir, "CHAT_WINDOW_CRASH_PHASE="+phase)
			output, err := os.Create(filepath.Join(dir, "child.log"))
			if err != nil {
				t.Fatal(err)
			}
			defer output.Close()
			cmd.Stdout = output
			cmd.Stderr = output
			if err = cmd.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { _ = cmd.Process.Kill() }()
			deadline := time.Now().Add(20 * time.Second)
			for {
				if _, err = os.Stat(filepath.Join(dir, "ready")); err == nil {
					break
				}
				if time.Now().After(deadline) {
					b, _ := os.ReadFile(filepath.Join(dir, "child.log"))
					t.Fatalf("child never reached failpoint: %s", b)
				}
				time.Sleep(10 * time.Millisecond)
			}
			if err = cmd.Process.Kill(); err != nil {
				t.Fatal(err)
			}
			_ = cmd.Wait()
			d, err = NewDataBase(ctx, "window-crash", dir, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer d.Close(ctx)
			w, err := d.ReadMessageWindow(ctx, "chat", 40, 2)
			if err != nil {
				t.Fatal(err)
			}
			want := 1
			if phase == "after" {
				want = 2
			}
			if len(w.Rows) != want || w.Conversation.MaxSeq != int64(want) || w.Conversation.UnreadCount != int32(want) {
				t.Fatalf("partial commit after kill: %+v rows=%d", w.Conversation, len(w.Rows))
			}
			// Replay after a lost receipt must not duplicate a committed message.
			if err = d.CommitMessageSyncBatch(ctx, nil, map[string][]*model_struct.LocalChatLog{"chat": {{ClientMsgID: "m2", Seq: 2}}}, []*model_struct.LocalConversation{{ConversationID: "chat", MaxSeq: 2, UnreadCount: 2}}, nil); err != nil {
				t.Fatal(err)
			}
			w, err = d.ReadMessageWindow(ctx, "chat", 40, 2)
			if err != nil || len(w.Rows) != 2 {
				t.Fatalf("replay: %+v %v", w, err)
			}
		})
	}
}
