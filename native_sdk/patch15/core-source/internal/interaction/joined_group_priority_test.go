package interaction

import (
	"context"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

func TestMessageRecoveryAllowsBoundedGroupPageToFinish(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	input := make(chan common.Cmd2Value, 8)
	started, pageDone, messages, done := make(chan struct{}, 8), make(chan bool, 8), make(chan struct{}, 8), make(chan struct{})
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
			select {
			case <-time.After(200 * time.Millisecond):
				pageDone <- true
			case <-c.Ctx.Done():
				pageDone <- false
			}
		})
	}()
	defer func() { cancel(); <-done }()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
	<-started
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	select {
	case ok := <-pageDone:
		if !ok {
			t.Fatal("message recovery cancelled the protected group page")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("group page stalled")
	}
	select {
	case <-messages:
	case <-time.After(2 * time.Second):
		t.Fatal("message recovery lost")
	}
}
