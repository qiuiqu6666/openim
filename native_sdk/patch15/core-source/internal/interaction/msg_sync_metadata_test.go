package interaction

import (
	"errors"
	"fmt"
	"sync/atomic"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func TestOfflineLatestPrecedesFailingMetadataWithoutPush(t *testing.T) {
	for _, wake := range []bool{false, true} {
		for _, tail := range []int64{6, 100000000} {
			t.Run(fmt.Sprintf("wake=%v/tail=%d", wake, tail), func(t *testing.T) {
				ctx := recoveryContext(t)
				conn := &LongConnMgr{send: make(chan Message, 1)}
				m := &MsgSyncer{ctx: ctx, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"si_peer": 5}}
				var visible, metadataCalls, terminal atomic.Int64
				visible.Store(5)
				failMetadata := true
				receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
					if cmd.Cmd == constant.CmdSyncData {
						metadataCalls.Add(1)
						if visible.Load() != tail {
							t.Error("metadata ran before latest message became visible")
						}
						if failMetadata {
							return errors.New("profile service unavailable")
						}
					}
					if cmd.Cmd == constant.CmdSyncFlag {
						terminal.Store(int64(cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).SyncFlag))
					}
					if cmd.Cmd == constant.CmdNewMsgCome {
						for _, packet := range cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs {
							for _, row := range packet.Msgs {
								if row.Seq > visible.Load() {
									visible.Store(row.Seq)
								}
							}
						}
					}
					return nil
				})
				requestWorker(t, conn, func(req Message) *GeneralWsResp {
					if req.Message.ReqIdentifier == constant.GetNewestSeq {
						return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"si_peer": tail}})
					}
					return requestedRecoveryResponse(t, req)
				})
				run := func() {
					m.startSync()
					if wake {
						m.doWakeupDataSync(ctx)
					} else {
						m.doConnected(ctx)
					}
				}
				run()
				// Flush the terminal command through the same serialized worker.
				if err := common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: "barrier"}, m.conversationCh); err != nil {
					t.Fatal(err)
				}
				if visible.Load() != tail || metadataCalls.Load() != 1 || terminal.Load() != constant.MsgSyncFailed {
					t.Fatalf("tail=%d metadata=%d status=%d", visible.Load(), metadataCalls.Load(), terminal.Load())
				}
				failMetadata = false
				run()
				if err := common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: "barrier"}, m.conversationCh); err != nil {
					t.Fatal(err)
				}
				if metadataCalls.Load() != 2 || terminal.Load() != constant.MsgSyncEnd {
					t.Fatal("metadata obligation was not retried")
				}
			})
		}
	}
}
