//go:build cgo && !js

package interaction

import (
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"google.golang.org/protobuf/proto"
)

func TestContiguousSQLiteLegacyGapAndInterruptedCheckpoint(t *testing.T) {
	ctx := recoveryContext(t)
	dir := t.TempDir()
	d, err := db.NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.Close(ctx) })
	if err = d.SetAppSDKVersion(ctx, &model_struct.LocalAppSDKVersion{Installed: true}); err != nil {
		t.Fatal(err)
	}
	if err = d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", LatestMsgSendTime: 3, ConversationType: constant.SingleChatType}}); err != nil {
		t.Fatal(err)
	}
	// Legacy recovery.12 left a tail at 13 but never received 4..12.
	for _, seq := range []int64{1, 2, 3, 13} {
		if err = d.BatchInsertMessageList(ctx, "chat", []*model_struct.LocalChatLog{{ClientMsgID: fmt.Sprint(seq), Seq: seq}}); err != nil {
			t.Fatal(err)
		}
	}
	m, err := NewMsgSyncer(ctx, make(chan common.Cmd2Value), nil, "self", nil, d, 0)
	if err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["chat"] != 0 {
		t.Fatalf("MAX(seq) trusted as coverage: %v", m.syncedMaxSeqs)
	}
	if err = m.rememberMessageTarget(ctx, "chat", 13); err != nil {
		t.Fatal(err)
	}
	// Simulate the process disappearing after storage, before the checkpoint.
	rows := make([]*model_struct.LocalChatLog, 0, 13)
	for seq := int64(1); seq <= 13; seq++ {
		rows = append(rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(seq), Seq: seq})
	}
	if err = d.CommitMessageSyncBatch(ctx, nil, map[string][]*model_struct.LocalChatLog{"chat": rows}, []*model_struct.LocalConversation{{ConversationID: "chat", LatestMsgSendTime: 13, UnreadCount: 10}}, nil); err != nil {
		t.Fatal(err)
	}
	if err = d.Close(ctx); err != nil {
		t.Fatal(err)
	}
	d, err = db.NewDataBase(ctx, "self", dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m, err = NewMsgSyncer(ctx, make(chan common.Cmd2Value), nil, "self", conn, d, 0)
	if err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["chat"] != 0 {
		t.Fatal("restart skipped interrupted receipt")
	}
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		p := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
		var rows []*model_struct.LocalChatLog
		for _, row := range p.Msgs["chat"].Msgs {
			rows = append(rows, &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(row.Seq), Seq: row.Seq})
		}
		return d.CommitMessageSyncBatch(ctx, nil, map[string][]*model_struct.LocalChatLog{"chat": rows}, nil, nil)
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		p := &sdkws.PullMessageBySeqsReq{}
		if err := proto.Unmarshal(req.Message.Data, p); err != nil {
			panic(err)
		}
		var seqs []int64
		for s := p.SeqRanges[0].Begin; s <= p.SeqRanges[0].End; s++ {
			seqs = append(seqs, s)
		}
		return wireResponse(&sdkws.PullMessageBySeqsResp{Msgs: recoveryMsgs("chat", seqs...)})
	})
	// Even an old maximum observation cannot erase the durable target.
	if err = m.compareSeqsAndBatchSync(ctx, map[string]int64{"chat": 3}, 1); err != nil {
		t.Fatal(err)
	}
	if m.syncedMaxSeqs["chat"] != 13 {
		t.Fatal("did not complete durable target")
	}
	for seq := int64(1); seq <= 13; seq++ {
		if _, err = d.GetMessageBySeq(ctx, "chat", seq); err != nil {
			t.Fatalf("missing %d: %v", seq, err)
		}
	}
	c, err := d.GetConversation(ctx, "chat")
	if err != nil || c.UnreadCount != 10 {
		t.Fatalf("replay changed unread: %+v %v", c, err)
	}
	restarted, err := NewMsgSyncer(ctx, make(chan common.Cmd2Value), nil, "self", nil, d, 0)
	if err != nil {
		t.Fatal(err)
	}
	if restarted.syncedMaxSeqs["chat"] != 13 {
		t.Fatal("committed checkpoint did not survive reload")
	}
}
