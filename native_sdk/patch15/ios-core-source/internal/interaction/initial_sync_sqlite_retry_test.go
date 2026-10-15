//go:build cgo && !js

package interaction

import (
	"errors"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func TestInitialSQLiteSyncRetriesAfterMessageFailure(t *testing.T) {
	for _, stage := range []string{"pull", "storage", "restart"} {
		t.Run(stage, func(t *testing.T) {
			ctx := recoveryContext(t)
			dir := t.TempDir()
			d, err := db.NewDataBase(ctx, "self", dir, 0)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = d.Close(ctx) })
			if err := d.BatchInsertConversationList(ctx, []*model_struct.LocalConversation{{ConversationID: "chat", ConversationType: constant.SingleChatType}}); err != nil {
				t.Fatal(err)
			}
			conn := &LongConnMgr{send: make(chan Message, 1)}
			conn.SetConnectionStatus(Connected)
			conversationCh := make(chan common.Cmd2Value)
			m, err := NewMsgSyncer(ctx, conversationCh, nil, "self", conn, d, 0)
			if err != nil {
				t.Fatal(err)
			}
			// The app has its metadata, but has not committed its first messages.
			m.reinstalled = true
			flags := make(chan int, 8)
			storageAttempts := 0
			receiptWorker(t, conversationCh, func(cmd common.Cmd2Value) error {
				if cmd.Cmd == constant.CmdSyncFlag {
					flags <- cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).SyncFlag
				}
				if cmd.Cmd == constant.CmdMsgSyncInReinstall {
					storageAttempts++
					if stage == "storage" && storageAttempts == 1 {
						return errors.New("simulated disk write failure")
					}
					batch := cmd.Value.(sdk_struct.CmdMsgSyncInReinstall)
					inserts := map[string][]*model_struct.LocalChatLog{}
					for id, rows := range batch.Msgs {
						for _, row := range rows.Msgs {
							inserts[id] = append(inserts[id], &model_struct.LocalChatLog{ClientMsgID: fmt.Sprint(row.Seq), Seq: row.Seq})
						}
					}
					return d.CommitMessageSyncBatch(ctx, nil, inserts, nil, nil)
				}
				return nil
			})
			pulls := 0
			observations := 0
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.GetNewestSeq {
					observations++
					notificationSeq := int64(7)
					if observations > 1 {
						notificationSeq = 5
					} // A stale retry response.
					return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"n_chat": notificationSeq, "chat": 3}})
				}
				pulls++
				if stage != "storage" && pulls == 1 {
					return &GeneralWsResp{ErrCode: 10001, ErrMsg: "simulated connection loss"}
				}
				return requestedRecoveryResponse(t, req)
			})
			m.startSync()
			m.doConnected(ctx)
			if <-flags != constant.AppDataSyncStart || <-flags != constant.MsgSyncFailed {
				t.Fatal("failure did not terminate initial sync")
			}
			version, err := d.GetAppSDKVersion(ctx)
			if err != nil || version.Installed || !m.reinstalled || m.syncedMaxSeqs["chat"] != 0 {
				t.Fatalf("failure committed initialization: %+v %v", version, err)
			}
			if stage == "restart" {
				if err := d.Close(ctx); err != nil {
					t.Fatal(err)
				}
				d, err = db.NewDataBase(ctx, "self", dir, 0)
				if err != nil {
					t.Fatal(err)
				}
				m, err = NewMsgSyncer(ctx, conversationCh, nil, "self", conn, d, 0)
				if err != nil {
					t.Fatal(err)
				}
			}
			// No new push or user action is needed for a foreground retry.
			m.doMessageSeqReconciliation(ctx)
			if <-flags != constant.AppDataSyncStart || <-flags != constant.AppDataSyncFinish {
				t.Fatal("retry did not finish initial sync")
			}
			version, err = d.GetAppSDKVersion(ctx)
			if err != nil || !version.Installed || m.reinstalled || m.syncedMaxSeqs["chat"] != 3 {
				t.Fatalf("retry failed: %+v %v", version, err)
			}
			if m.syncedMaxSeqs["n_chat"] != 7 {
				t.Fatalf("stale retry rewound in-memory notification baseline to %d", m.syncedMaxSeqs["n_chat"])
			}
			for seq := int64(1); seq <= 3; seq++ {
				if _, err := d.GetMessageBySeq(ctx, "chat", seq); err != nil {
					t.Fatalf("missing committed message %d: %v", seq, err)
				}
			}
		})
	}
}
