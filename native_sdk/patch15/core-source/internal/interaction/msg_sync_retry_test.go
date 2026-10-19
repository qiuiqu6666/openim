package interaction

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

func TestNoProgressRetryBackoffCapsAndResetsOnProgress(t *testing.T) {
	var r messageSyncRetry
	now := time.Unix(100, 0)
	for _, seconds := range []int{1, 2, 4, 8, 16, 30, 30, 30} {
		r.failed(now, false)
		if got := r.remaining(now); got != time.Duration(seconds)*time.Second {
			t.Fatalf("delay=%v want=%ds", got, seconds)
		}
		now = r.next
	}
	r.failed(now, true)
	if r.remaining(now) != time.Second {
		t.Fatal("committed progress did not reset backoff")
	}
}

func TestNoProgressRetryCoalescesSignalsAndDeliversLivePush(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	input := make(chan common.Cmd2Value, 100)
	attempts := make(chan struct{}, 10)
	live := make(chan struct{}, 100)
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == constant.CmdPushMsg {
				live <- struct{}{}
				return
			}
			recordMessageSyncFailure(cmd.Ctx, errors.New("unchanged missing range"))
			attempts <- struct{}{}
		})
	}()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	select {
	case <-attempts:
	case <-time.After(time.Second):
		t.Fatal("initial sync not started")
	}
	for n := 0; n < 30; n++ {
		input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
		input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
	}
	for n := 0; n < 30; n++ {
		select {
		case <-live:
		case <-time.After(250 * time.Millisecond):
			t.Fatal("retry backoff blocked live delivery")
		}
	}
	select {
	case <-attempts:
		t.Fatal("incoming signals bypassed backoff")
	case <-time.After(150 * time.Millisecond):
	}
	select {
	case <-attempts:
	case <-time.After(2 * time.Second):
		t.Fatal("retry was lost without another message")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(250 * time.Millisecond):
		t.Fatal("logout waited for retry timer")
	}
}

func TestCancelledAttemptDoesNotBecomeFailedRecovery(t *testing.T) {
	owner := &messagePageCoordinator{}
	ctx, cancel := context.WithCancel(context.WithValue(context.Background(), messagePageContextKey{}, owner))
	cancel()
	recordMessageSyncFailure(ctx, context.Canceled)
	if owner.failed.Load() {
		t.Fatal("preemption increased backoff")
	}
}

func TestLivePreemptionCannotBypassRecordedFailure(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	input := make(chan common.Cmd2Value, 4)
	started, live, done := make(chan struct{}, 4), make(chan struct{}, 1), make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == constant.CmdPushMsg {
				live <- struct{}{}
				return
			}
			recordMessageSyncFailure(cmd.Ctx, errors.New("range already failed"))
			started <- struct{}{}
			<-cmd.Ctx.Done()
		})
	}()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	<-started
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
	select {
	case <-live:
	case <-time.After(time.Second):
		t.Fatal("live push blocked")
	}
	select {
	case <-started:
		t.Fatal("preemption bypassed no-progress cooldown")
	case <-time.After(150 * time.Millisecond):
	}
	cancel()
	<-done
}

func TestRetryCooldownDrainsMoreThanOneBurstOfQueuedLiveMessages(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	input := make(chan common.Cmd2Value, 100)
	started, live, done := make(chan struct{}), make(chan struct{}, 70), make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == constant.CmdPushMsg {
				live <- struct{}{}
				return
			}
			owner := cmd.Ctx.Value(messagePageContextKey{}).(*messagePageCoordinator)
			owner.bounded.Store(true)
			recordMessageSyncFailure(cmd.Ctx, errors.New("failed bounded page"))
			close(started)
			<-cmd.Ctx.Done()
		})
	}()
	defer func() { cancel(); <-done }()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	<-started
	for n := 0; n < 70; n++ {
		input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
	}
	deadline := time.After(500 * time.Millisecond)
	for n := 0; n < 70; n++ {
		select {
		case <-live:
		case <-deadline:
			t.Fatalf("only %d queued live messages delivered during cooldown", n)
		}
	}
}
