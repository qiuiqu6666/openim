//go:build cgo && !js

package db

import (
	"context"
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/protocol/sdkws"
	"strings"
	"testing"
)

func cacheTestDB(t *testing.T) (*DataBase, context.Context) {
	t.Helper()
	ctx := context.Background()
	d, err := NewDataBase(ctx, "cache-test", t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(ctx) })
	return d, ctx
}

func cacheTestRows(first, last int) []*model_struct.LocalChatLog {
	var rows []*model_struct.LocalChatLog
	for seq := first; seq <= last; seq++ {
		rows = append(rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(seq), Seq: int64(seq), SendTime: int64(seq), Status: constant.MsgStatusSendSuccess, Content: `{"content":"message"}`})
	}
	return rows
}

func TestCacheEvictionRetainsUnreadPendingAndPagingAnchor(t *testing.T) {
	d, ctx := cacheTestDB(t)
	if err := d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", UnreadCount: 99000, LatestMsg: `{"seq":1200}`}}); err != nil {
		t.Fatal(err)
	}
	rows := append(cacheTestRows(1, 1000), &model_struct.LocalChatLog{ClientMsgID: "pending", Status: constant.MsgStatusSending}, &model_struct.LocalChatLog{ClientMsgID: "failed", Status: constant.MsgStatusSendFailed}, &model_struct.LocalChatLog{ClientMsgID: "deleted", Seq: 99999, Status: constant.MsgStatusHasDeleted})
	if err := d.BatchInsertMessageList(ctx, "chat", rows); err != nil {
		t.Fatal(err)
	}
	if err := d.MaintainMessageCache(ctx, "chat", nil); err != nil {
		t.Fatal(err)
	}
	newRows := cacheTestRows(1001, 1200)
	if err := d.SaveMessageCacheCursors(ctx, "chat", 0, false, true, cacheTestRows(1, 40)); err != nil {
		t.Fatal(err)
	}
	if err := d.BatchInsertMessageMap(ctx, map[string][]*model_struct.LocalChatLog{"chat": newRows}); err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, row := range newRows {
		ids = append(ids, row.ClientMsgID)
	}
	if err := d.MaintainMessageCache(ctx, "chat", ids); err != nil {
		t.Fatal(err)
	}
	var count int64
	d.conn.Table(utils.GetTableName("chat")).Count(&count)
	if count != 1003 {
		t.Fatalf("cache count %d, want 1000 + 3 protected rows", count)
	}
	anchor, err := d.GetMessageCacheAnchor(ctx, "chat", "100")
	if err != nil || anchor.Seq != 100 {
		t.Fatalf("evicted cursor: %+v %v", anchor, err)
	}
	// Even after the ordinary eviction-anchor budget has rolled over, the
	// currently installed forward and reverse paging positions remain usable.
	if err := d.conn.Where("conversation_id = ?", "chat").Delete(&messageCacheAnchor{}).Error; err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"1", "40"} {
		if _, err := d.GetMessageCacheAnchor(ctx, "chat", id); err != nil {
			t.Fatal("active cursor lost", id, err)
		}
	}
	conv, err := d.GetConversation(ctx, "chat")
	if err != nil || conv.UnreadCount != 99000 || conv.LatestMsg != `{"seq":1200}` {
		t.Fatalf("cache changed conversation: %+v %v", conv, err)
	}
	// Scrolling back is allowed to replace cold cached rows with older content.
	if err := d.BatchInsertMessageMap(ctx, map[string][]*model_struct.LocalChatLog{"chat": cacheTestRows(1, 40)}); err != nil {
		t.Fatal(err)
	}
	ids = nil
	for seq := 1; seq <= 40; seq++ {
		ids = append(ids, fmt.Sprint(seq))
	}
	if err := d.MaintainMessageCache(ctx, "chat", ids); err != nil {
		t.Fatal(err)
	}
	if _, err := d.GetMessage(ctx, "chat", "1"); err != nil {
		t.Fatal("requested historical page was evicted", err)
	}
	for _, id := range []string{"pending", "failed", "deleted"} {
		if _, err := d.GetMessage(ctx, "chat", id); err != nil {
			t.Fatal(id, err)
		}
	}
}

func TestCacheAccountAndByteBudgets(t *testing.T) {
	d, ctx := cacheTestDB(t)
	for group := 0; group < 21; group++ {
		id := fmt.Sprintf("group_%d", group)
		if err := d.BatchInsertMessageList(ctx, id, cacheTestRows(1, 1000)); err != nil {
			t.Fatal(err)
		}
		if err := d.MaintainMessageCache(ctx, id, nil); err != nil {
			t.Fatal(err)
		}
	}
	var count int64
	d.conn.Model(&messageCacheEntry{}).Count(&count)
	if count != MessageCacheAccountLimit {
		t.Fatalf("account cache %d", count)
	}
	large := cacheTestRows(1, 70)
	for _, row := range large {
		row.Content = strings.Repeat("x", 1<<20)
	}
	if err := d.BatchInsertMessageList(ctx, "large", large); err != nil {
		t.Fatal(err)
	}
	if err := d.MaintainMessageCache(ctx, "large", nil); err != nil {
		t.Fatal(err)
	}
	var bytes int64
	d.conn.Model(&messageCacheEntry{}).Select("coalesce(sum(bytes),0)").Scan(&bytes)
	if bytes > MessageCacheByteLimit {
		t.Fatalf("byte budget exceeded: %d", bytes)
	}
}

func TestRecallSurvivesUncachedOriginalRestartAndRefetch(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	d, err := NewDataBase(ctx, "recall", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.SaveMessageRevocation(ctx, &sdkws.RevokeMsgTips{ConversationID: "chat", Seq: 7, RevokerUserID: "sender", RevokeTime: 12}); err != nil {
		t.Fatal(err)
	}
	if err := d.Close(ctx); err != nil {
		t.Fatal(err)
	}
	d, err = NewDataBase(ctx, "recall", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	if err := d.BatchInsertMessageMap(ctx, map[string][]*model_struct.LocalChatLog{"chat": cacheTestRows(7, 7)}); err != nil {
		t.Fatal(err)
	}
	row, err := d.GetMessageBySeq(ctx, "chat", 7)
	if err != nil || row.ContentType != constant.RevokeNotification {
		t.Fatalf("recall resurrected: %+v %v", row, err)
	}
}

func TestReadWatermarkSurvivesRestartAndHistoryCacheMiss(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	d, err := NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.SaveMessageReadWatermarks(ctx, map[string]int64{"chat": 1000}, true, 5); err != nil {
		t.Fatal(err)
	}
	if err := d.SaveMessageReadWatermarks(ctx, map[string]int64{"chat": 500}, true, 3); err != nil {
		t.Fatal(err)
	}
	if err := d.SaveMessageReadWatermarks(ctx, map[string]int64{"chat": 800}, false, 4); err != nil {
		t.Fatal(err)
	}
	if err := d.Close(ctx); err != nil {
		t.Fatal(err)
	}
	d, err = NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close(ctx)
	rows := []*model_struct.LocalChatLog{
		{ClientMsgID: "peer900", SendID: "peer", Seq: 900, Status: constant.MsgStatusSendSuccess},
		{ClientMsgID: "peer1001", SendID: "peer", Seq: 1001, Status: constant.MsgStatusSendSuccess},
		{ClientMsgID: "self700", SendID: "self", Seq: 700, Status: constant.MsgStatusSendSuccess},
		{ClientMsgID: "self900", SendID: "self", Seq: 900, Status: constant.MsgStatusSendSuccess},
	}
	if err := d.BatchInsertMessageMap(ctx, map[string][]*model_struct.LocalChatLog{"chat": rows}); err != nil {
		t.Fatal(err)
	}
	for index, want := range []bool{true, false, true, false} {
		row, err := d.GetMessage(ctx, "chat", rows[index].ClientMsgID)
		if err != nil || row.IsRead != want {
			t.Fatalf("read watermark for %s: %+v %v", rows[index].ClientMsgID, row, err)
		}
	}
}

func TestCacheEvictionFailureRollsBackLedgerAndMessages(t *testing.T) {
	d, ctx := cacheTestDB(t)
	if err := d.BatchInsertMessageList(ctx, "chat", cacheTestRows(1, 1000)); err != nil {
		t.Fatal(err)
	}
	if err := d.MaintainMessageCache(ctx, "chat", nil); err != nil {
		t.Fatal(err)
	}
	if err := d.BatchInsertMessageList(ctx, "chat", cacheTestRows(1001, 1001)); err != nil {
		t.Fatal(err)
	}
	if err := d.conn.Exec("CREATE TRIGGER fail_cache_delete BEFORE DELETE ON chat_logs_chat BEGIN SELECT RAISE(ABORT, 'injected cache error'); END").Error; err != nil {
		t.Fatal(err)
	}
	if err := d.MaintainMessageCache(ctx, "chat", []string{"1001"}); err == nil {
		t.Fatal("expected injected failure")
	}
	var count int64
	d.conn.Model(&messageCacheEntry{}).Count(&count)
	if count != 1000 {
		t.Fatal("ledger did not roll back", count)
	}
	if _, err := d.GetMessage(ctx, "chat", "1"); err != nil {
		t.Fatal("message lost during failed eviction", err)
	}
	d.conn.Exec("DROP TRIGGER fail_cache_delete")
	if err := d.MaintainMessageCache(ctx, "chat", []string{"1001"}); err != nil {
		t.Fatal(err)
	}
}

func TestLegacyCacheMigrationKeepsRecallAndDeleteMarkers(t *testing.T) {
	d, ctx := cacheTestDB(t)
	rows := append(cacheTestRows(1, 1100),
		&model_struct.LocalChatLog{ClientMsgID: "legacy-recall", Seq: 1, Status: constant.MsgStatusSendSuccess, ContentType: constant.RevokeNotification, Content: `{"detail":"{}"}`},
		&model_struct.LocalChatLog{ClientMsgID: "legacy-delete", Seq: 2, Status: constant.MsgStatusHasDeleted, Content: "discard deleted body"})
	if err := d.BatchInsertMessageList(ctx, "legacy", rows); err != nil {
		t.Fatal(err)
	}
	if err := d.initializeMessageCache(ctx, []string{"chat_logs_legacy"}); err != nil {
		t.Fatal(err)
	}
	row, err := d.GetMessage(ctx, "legacy", "legacy-recall")
	if err != nil || row.ContentType != constant.RevokeNotification {
		t.Fatal("legacy recall was evicted", err)
	}
	row, err = d.GetMessage(ctx, "legacy", "legacy-delete")
	if err != nil || row.Status != constant.MsgStatusHasDeleted || row.Content != "" {
		t.Fatalf("invalid delete marker: %+v %v", row, err)
	}
	var count int64
	d.conn.Model(&messageCacheEntry{}).Count(&count)
	if count != 1000 {
		t.Fatal("legacy cache budget", count)
	}
}
