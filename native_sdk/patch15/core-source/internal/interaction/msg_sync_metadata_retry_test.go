package interaction

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

func TestMetadataCooldownDoesNotDelayMessageRecovery(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	input := make(chan common.Cmd2Value, 100)
	auxiliary, messages, done := make(chan struct{}, 10), make(chan struct{}, 10), make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == cmdSyncAuxiliaryMetadata {
				recordMessageSyncFailure(cmd.Ctx, errors.New("profile unavailable"))
				auxiliary <- struct{}{}
			} else {
				messages <- struct{}{}
			}
		})
	}()
	defer func() { cancel(); <-done }()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
	<-auxiliary
	for i := 0; i < 30; i++ {
		input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
	}
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	select {
	case <-messages:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("metadata cooldown blocked message recovery")
	}
	select {
	case <-auxiliary:
		t.Fatal("signals bypassed metadata cooldown")
	case <-time.After(100 * time.Millisecond):
	}
	select {
	case <-auxiliary:
	case <-time.After(2 * time.Second):
		t.Fatal("metadata retry lost")
	}
}

func TestMetadataAlwaysYieldsWithoutReservingSlowRetry(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	input := make(chan common.Cmd2Value, 10)
	auxiliary, live, done := make(chan struct{}, 10), make(chan struct{}, 10), make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == cmdSyncAuxiliaryMetadata {
				auxiliary <- struct{}{}
				<-cmd.Ctx.Done()
			} else {
				live <- struct{}{}
			}
		})
	}()
	defer func() { cancel(); <-done }()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
	for attempt := 0; attempt < 2; attempt++ {
		select {
		case <-auxiliary:
		case <-time.After(2 * time.Second):
			t.Fatal("metadata did not resume")
		}
		input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
		select {
		case <-live:
		case <-time.After(300 * time.Millisecond):
			t.Fatal("metadata retry blocked live push")
		}
	}
	select {
	case <-auxiliary:
		t.Fatal("cancel/retry hot loop")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestMessageRecoveryPreemptsActiveMetadataAndRetainsObligation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	input := make(chan common.Cmd2Value, 10)
	auxiliary, message, done := make(chan struct{}, 10), make(chan struct{}, 1), make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(cmd common.Cmd2Value) {
			if cmd.Cmd == cmdSyncAuxiliaryMetadata {
				auxiliary <- struct{}{}
				<-cmd.Ctx.Done()
			} else {
				message <- struct{}{}
			}
		})
	}()
	defer func() { cancel(); <-done }()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
	<-auxiliary
	input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdIMMessageSync}
	select {
	case <-message:
	case <-time.After(300 * time.Millisecond):
		t.Fatal("message sync lost or blocked")
	}
	select {
	case <-auxiliary:
	case <-time.After(2 * time.Second):
		t.Fatal("preempted metadata lost")
	}
}

func TestAuxiliaryProgressSurvivesRetryButNotNewObligation(t *testing.T) {
	ctx := recoveryContext(t)
	m := &MsgSyncer{ctx: ctx, recvCh: make(chan common.Cmd2Value, 10), conversationCh: make(chan common.Cmd2Value)}
	userCalls, friendCalls := 0, 0
	fail := true
	receiptWorker(t, m.conversationCh, func(cmd common.Cmd2Value) error {
		if err := common.RunMetadataStage(cmd.Ctx, "user", func(context.Context) error { userCalls++; return nil }); err != nil {
			return err
		}
		return common.RunMetadataStage(cmd.Ctx, "friends", func(context.Context) error {
			friendCalls++
			if fail {
				return errors.New("offline")
			}
			return nil
		})
	})
	m.requestAuxiliaryMetadata()
	m.doAuxiliaryMetadataSync(ctx)
	m.requestAuxiliaryMetadata() // Duplicate recovery must not erase checkpoints.
	fail = false
	m.doAuxiliaryMetadataSync(ctx)
	if userCalls != 1 || friendCalls != 2 || m.auxMetadataPending {
		t.Fatalf("user=%d friends=%d pending=%v", userCalls, friendCalls, m.auxMetadataPending)
	}
	m.requestAuxiliaryMetadata()
	m.doAuxiliaryMetadataSync(ctx)
	if userCalls != 2 || friendCalls != 3 {
		t.Fatal("new obligation reused old completion")
	}
}
