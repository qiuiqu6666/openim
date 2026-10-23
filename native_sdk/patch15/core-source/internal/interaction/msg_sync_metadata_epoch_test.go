package interaction

import (
	"context"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/protocol/sdkws"
	"testing"
)

// Recovery must converge after a real transport change.
// Uses the production doConnected and auxiliary scheduling entry points.
func TestReconnectRefreshesCompletedProfileStage(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, db: &recoveryVersionDB{installed: true}, longConnMgr: conn,
		recvCh: make(chan common.Cmd2Value, 10), conversationCh: make(chan common.Cmd2Value),
		syncedMaxSeqs: map[string]int64{}}
	serverName, localName, reads := "before-disconnect", "", 0
	failOtherStage := true
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd != constant.CmdSyncData {
			return nil
		}
		if err := common.RunMetadataStage(cmd.Ctx, "groups", func(context.Context) error {
			reads++
			localName = serverName
			return nil
		}); err != nil {
			return err
		}
		return common.RunMetadataStage(cmd.Ctx, "friends", func(context.Context) error {
			if failOtherStage {
				return errors.New("temporary unrelated failure")
			}
			return nil
		})
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{}})
	})
	conn.metrics.generation.Add(1)
	m.doConnected(ctx)
	m.doAuxiliaryMetadataSync(ctx)
	if !m.auxMetadataPending || reads != 1 {
		t.Fatal("invalid fixture")
	}
	// Another user changes the group while this session is disconnected.
	serverName = "changed-while-offline"
	failOtherStage = false
	conn.metrics.generation.Add(1)
	m.doConnected(ctx)
	m.doAuxiliaryMetadataSync(ctx)
	m.doAuxiliaryMetadataSync(ctx) // Fresh follow-up after the old resumable pass.
	if reads != 2 || localName != serverName || m.auxMetadataPending {
		t.Fatalf("recovery did not converge: reads=%d local=%q pending=%v", reads, localName, m.auxMetadataPending)
	}
	t.Logf("VERIFIED: reconnect finished with local=%q server=%q reads=%d pending=%v", localName, serverName, reads, m.auxMetadataPending)
}

func TestReconnectRefreshesCompletedGroupAfterResumingSweep(t *testing.T) {
	ctx := recoveryContext(t)
	conn := &LongConnMgr{send: make(chan Message, 1)}
	m := &MsgSyncer{ctx: ctx, db: &recoveryVersionDB{installed: true}, longConnMgr: conn,
		recvCh: make(chan common.Cmd2Value, 10), conversationCh: make(chan common.Cmd2Value),
		syncedMaxSeqs: map[string]int64{}}
	serverName, localName, reads := "old-group-a", "", 0
	failB := true
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if cmd.Cmd != constant.CmdSyncData {
			return nil
		}
		return common.RunMetadataStage(cmd.Ctx, "groups", func(stage context.Context) error {
			for _, id := range common.PendingMetadataItems(stage, "group-members", []string{"a", "b"}) {
				if id == "b" && failB {
					return errors.New("group b temporarily unavailable")
				}
				if id == "a" {
					reads++
					localName = serverName
				}
				common.CompleteMetadataItem(stage, "group-members", id)
			}
			common.FinishMetadataItems(stage, "group-members")
			return nil
		})
	})
	requestWorker(t, conn, func(req Message) *GeneralWsResp {
		return wireResponse(&sdkws.GetMaxSeqResp{MaxSeqs: map[string]int64{}})
	})
	conn.metrics.generation.Add(1)
	m.doConnected(ctx)
	m.doAuxiliaryMetadataSync(ctx)
	if !m.auxMetadataPending || reads != 1 {
		t.Fatal("invalid fixture")
	}
	serverName = "group-a-changed-during-disconnect"
	failB = false
	conn.metrics.generation.Add(1)
	m.doConnected(ctx)
	m.doAuxiliaryMetadataSync(ctx)
	m.doAuxiliaryMetadataSync(ctx)
	if reads != 2 || localName != serverName || m.auxMetadataPending {
		t.Fatalf("recovery did not converge: reads=%d local=%q pending=%v", reads, localName, m.auxMetadataPending)
	}
	t.Logf("VERIFIED: completed group item survived reconnect; local=%q server=%q pending=%v", localName, serverName, m.auxMetadataPending)
}
