package interaction

import (
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"testing"
)

func TestInitialSyncRetriesWithoutNextMessage(t *testing.T) {
	for _, entry := range []string{"periodic", "manual"} {
		t.Run(entry, func(t *testing.T) {
			ctx := recoveryContext(t)
			conn := &LongConnMgr{send: make(chan Message, 1)}
			conn.SetConnectionStatus(Connected)
			d := &recoveryVersionDB{}
			m := &MsgSyncer{ctx: ctx, db: d, reinstalled: true, longConnMgr: conn, conversationCh: make(chan common.Cmd2Value), syncedMaxSeqs: map[string]int64{}}
			starts, stored := 0, 0
			receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
				if v, ok := cmd.Value.(sdk_struct.CmdNewMsgComeToConversation); ok && v.SyncFlag == constant.AppDataSyncStart {
					starts++
					if starts == 1 {
						return errors.New("temporary metadata failure")
					}
				}
				if v, ok := cmd.Value.(sdk_struct.CmdMsgSyncInReinstall); ok {
					for _, rows := range v.Msgs {
						stored += len(rows.Msgs)
					}
				}
				return nil
			})
			requestWorker(t, conn, func(req Message) *GeneralWsResp {
				if req.Message.ReqIdentifier == constant.GetNewestSeq {
					return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{"chat": 2}})
				}
				return requestedRecoveryResponse(t, req)
			})
			m.doConnected(ctx)
			if !m.reinstalled || d.installed {
				t.Fatal("failed initialization marked complete")
			}
			if entry == "periodic" {
				m.doMessageSeqReconciliation(ctx)
			} else {
				m.doIMMessageSync(ctx)
			}
			if starts != 2 || stored != 2 || !d.installed || m.reinstalled {
				t.Fatalf("starts=%d stored=%d installed=%v", starts, stored, d.installed)
			}
		})
	}
}

func TestInitialPushCannotBypassFailedMetadata(t *testing.T) {
	ctx := recoveryContext(t)
	d := &recoveryVersionDB{}
	m := &MsgSyncer{ctx: ctx, db: d, reinstalled: true, recvCh: make(chan common.Cmd2Value, 1), syncedMaxSeqs: map[string]int64{}}
	m.doPushMsg(ctx, &sdkws.PushMessages{Msgs: recoveryMsgs("chat", 1)})
	if m.syncedMaxSeqs["chat"] != 0 || m.checkpoints["chat"].Target != 1 || d.installed {
		t.Fatal("push bypassed required initialization")
	}
	if cmd := <-m.recvCh; cmd.Cmd != constant.CmdConnSuccesss {
		t.Fatal("push did not schedule initialization")
	}
}
