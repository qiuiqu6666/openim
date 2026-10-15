package interaction

import (
	"errors"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

func TestMessageRecoveryFinishesBeforeAuxiliaryMetadataAndRetainsItsRetry(t *testing.T) {
	for _, initial := range []bool{false, true} {
		t.Run(fmt.Sprint("initial=", initial), func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			m := &MsgSyncer{ctx: ctx, db: &recoveryVersionDB{installed: !initial}, reinstalled: initial, longConnMgr: conn, recvCh: make(chan common.Cmd2Value, 2), conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{"si_peer": 5}}
			metadata, delivered, terminal := 0, 0, 0
			failMetadata := true
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				if cmd.Cmd == constant.CmdSyncData {
					metadata++
					if !common.RecoveryMetadataPrepared(cmd.Ctx) {
						t.Error("required metadata receipt was forgotten")
					}
					if failMetadata {
						return errors.New("profile endpoint unavailable")
					}
					return nil
				}
				if cmd.Cmd == constant.CmdSyncFlag {
					terminal = cmd.Value.(sdk_struct.CmdNewMsgComeToConversation).SyncFlag
				}
				if cmd.Cmd == constant.CmdNewMsgCome {
					v := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation)
					if v.ReconcileReadSeq {
						t.Error("recovery repeated the already acknowledged read snapshot")
					}
					for _, p := range v.Msgs {
						delivered += len(p.Msgs)
					}
				}
				if cmd.Cmd == constant.CmdMsgSyncInReinstall {
					for _, p := range cmd.Value.(sdk_struct.CmdMsgSyncInReinstall).Msgs {
						delivered += len(p.Msgs)
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.GetNewestSeq {
					return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"si_peer": 6}})
				}
				return requestedRecoveryResponse(t, req)
			})
			m.doConnected(ctx)
			flush := func() {
				if err := common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: "barrier"}, m.conversationCh); err != nil {
					t.Fatal(err)
				}
			}
			flush()
			want := constant.MsgSyncEnd
			if initial {
				want = constant.AppDataSyncFinish
			}
			if terminal != want || delivered != 1 || metadata != 0 || !m.auxMetadataPending {
				t.Fatalf("messages=%d metadata=%d terminal=%d", delivered, metadata, terminal)
			}
			job := <-m.recvCh
			if job.Cmd != cmdSyncAuxiliaryMetadata {
				t.Fatal("auxiliary obligation was not queued")
			}
			m.doAuxiliaryMetadataSync(job.Ctx)
			flush()
			if !m.auxMetadataPending || terminal != want {
				t.Fatal("profile failure corrupted message readiness or disappeared")
			}
			m.queuePendingAuxiliaryMetadata()
			failMetadata = false
			m.doAuxiliaryMetadataSync((<-m.recvCh).Ctx)
			flush()
			if m.auxMetadataPending || metadata != 2 || delivered != 1 || terminal != want {
				t.Fatal("auxiliary retry lost work or replayed messages")
			}
		})
	}
}
