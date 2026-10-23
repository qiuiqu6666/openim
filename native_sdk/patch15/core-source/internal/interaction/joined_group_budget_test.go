package interaction

import (
	"context"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

func TestProtectedGroupPageStillYieldsAndHonorsLogout(t *testing.T) {
	for _, logout := range []bool{false, true} {
		t.Run(map[bool]string{false: "bounded-recovery", true: "logout"}[logout], func(t *testing.T) {
			ctx, cancel := context.WithCancel(recoveryContext(t))
			input := make(chan common.Cmd2Value, 8)
			started, messages, done := make(chan struct{}, 8), make(chan struct{}, 8), make(chan struct{})
			go func() {
				defer close(done)
				runMessageSyncLoop(ctx, input, func(c common.Cmd2Value) {
					if c.Cmd != cmdSyncAuxiliaryMetadata {
						messages <- struct{}{}
						return
					}
					finish := common.BeginMetadataBatch(c.Ctx)
					defer finish()
					started <- struct{}{}
					<-c.Ctx.Done()
				})
			}()
			defer func() { cancel(); <-done }()
			input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
			<-started
			if logout {
				cancel()
				select {
				case <-done:
				case <-time.After(300 * time.Millisecond):
					t.Fatal("page protection delayed logout")
				}
				return
			}
			input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdWakeUpDataSync}
			select {
			case <-messages:
			case <-time.After(2 * time.Second):
				t.Fatal("hung page blocked message recovery")
			}
		})
	}
}
