package interaction

import (
	"context"
	"errors"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

// Delay consumption until the scheduler has cleaned up the completed attempt.
// The UI must still receive its terminal status, but logout must invalidate it.
func TestWakeupResultSurvivesAttemptCleanup(t *testing.T) {
	for _, failed := range []bool{false, true} {
		name := "success"
		if failed {
			name = "failure"
		}
		t.Run(name, func(t *testing.T) {
			session, logout := context.WithCancel(recoveryContext(t))
			defer logout()
			attempt, cleanup := context.WithCancel(session)
			defer cleanup()
			conn := &LongConnMgr{send: make(chan Message, 1)}
			requestWorker(t, conn, func(Message) *GeneralWsResp {
				return wireResponse(&sdkws.GetMaxSeqResp{})
			})
			queue := make(chan common.Cmd2Value, 2)
			m := &MsgSyncer{ctx: session, longConnMgr: conn, conversationCh: queue, syncedMaxSeqs: map[string]int64{}}
			done := make(chan struct{})
			go func() { defer close(done); m.doWakeupDataSync(attempt) }()
			start := <-queue
			if failed {
				start.Receipt <- errors.New("metadata unavailable")
			} else {
				start.Receipt <- nil
				metadata := <-queue
				if metadata.Cmd != constant.CmdSyncData {
					t.Fatal("expected post-message metadata refresh")
				}
				metadata.Receipt <- nil
			}
			<-done
			cleanup()
			result := <-queue
			want := constant.MsgSyncEnd
			if failed {
				want = constant.MsgSyncFailed
			}
			if result.Value.(sdk_struct.CmdNewMsgComeToConversation).SyncFlag != want {
				t.Fatal("wrong terminal status")
			}
			if err := result.Ctx.Err(); err != nil {
				t.Fatalf("terminal callback discarded after attempt cleanup: %v", err)
			}
			logout()
			if result.Ctx.Err() == nil {
				t.Fatal("terminal callback outlived login session")
			}
		})
	}
}
