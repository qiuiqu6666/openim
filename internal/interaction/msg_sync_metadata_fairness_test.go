package interaction

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

type metadataFairWorker struct {
	queue     chan common.Cmd2Value
	started   chan struct{}
	completed chan struct{}
	updates   atomic.Int32
}

func (w *metadataFairWorker) GetCh() chan common.Cmd2Value { return w.queue }
func (w *metadataFairWorker) InterruptibleCommand(c common.Cmd2Value) bool {
	return c.Cmd == constant.CmdSyncData
}
func (w *metadataFairWorker) Work(c common.Cmd2Value) {
	if c.Cmd != constant.CmdSyncData {
		w.updates.Add(1)
		return
	}
	finish := common.BeginMetadataBatch(c.Ctx)
	defer finish()
	w.started <- struct{}{}
	select {
	case <-time.After(250 * time.Millisecond):
		w.completed <- struct{}{}
		c.Receipt <- nil
	case <-c.Ctx.Done():
		c.Receipt <- c.Ctx.Err()
	}
}

func TestMetadataSweepMakesProgressAcrossBusyRetries(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	input := make(chan common.Cmd2Value, 128)
	m := &MsgSyncer{ctx: ctx, recvCh: input, conversationCh: make(chan common.Cmd2Value)}
	var committed atomic.Int32
	var attempts atomic.Int32
	var live atomic.Int32
	finished := make(chan struct{}, 1)
	ids := []string{"0", "1", "2", "3", "4", "5", "6", "7"}
	receiptWorker(t, m.conversationCh, func(c common.Cmd2Value) error {
		for _, id := range common.PendingMetadataItems(c.Ctx, "test-groups", ids) {
			finish := common.BeginMetadataBatch(c.Ctx)
			select {
			case <-c.Ctx.Done():
				finish()
				return c.Ctx.Err()
			case <-time.After(180 * time.Millisecond):
				common.CompleteMetadataItem(c.Ctx, "test-groups", id)
				committed.Add(1)
				finish()
			}
		}
		finished <- struct{}{}
		return nil
	})
	done := make(chan struct{})
	go func() {
		defer close(done)
		runMessageSyncLoop(ctx, input, func(c common.Cmd2Value) {
			if c.Cmd == cmdSyncAuxiliaryMetadata {
				attempts.Add(1)
				m.doAuxiliaryMetadataSync(c.Ctx)
			} else {
				live.Add(1)
			}
		})
	}()
	producerDone := make(chan struct{})
	go func() {
		defer close(producerDone)
		ticker := time.NewTicker(5 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				select {
				case input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}:
				case <-ctx.Done():
					return
				}
			}
		}
	}()
	defer func() { cancel(); <-producerDone; <-done }()
	m.requestAuxiliaryMetadata()
	select {
	case <-finished:
	case <-time.After(6 * time.Second):
		t.Fatalf("sweep starved: committed=%d attempts=%d", committed.Load(), attempts.Load())
	}
	if committed.Load() != 8 || attempts.Load() < 2 || live.Load() == 0 {
		t.Fatalf("committed=%d attempts=%d live=%d", committed.Load(), attempts.Load(), live.Load())
	}
}

func TestBoundedMetadataCompletesUnderBothBusySchedulers(t *testing.T) {
	ctx, cancel := context.WithCancel(recoveryContext(t))
	input := make(chan common.Cmd2Value, 100)
	w := &metadataFairWorker{queue: make(chan common.Cmd2Value, 100), started: make(chan struct{}, 10), completed: make(chan struct{}, 10)}
	listenerDone, schedulerDone := make(chan struct{}), make(chan struct{})
	go func() { defer close(listenerDone); common.DoListener(ctx, w) }()
	var live atomic.Int32
	go func() {
		defer close(schedulerDone)
		runMessageSyncLoop(ctx, input, func(c common.Cmd2Value) {
			if c.Cmd == cmdSyncAuxiliaryMetadata {
				_ = common.SendSyncCmdWithReceipt(c.Ctx, common.Cmd2Value{Cmd: constant.CmdSyncData}, w.queue)
			} else {
				live.Add(1)
			}
		})
	}()
	defer func() { cancel(); <-schedulerDone; <-listenerDone }()
	input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
	select {
	case <-w.started:
	case <-time.After(time.Second):
		t.Fatal("metadata not started")
	}
	// Keep both queues busy beyond the old 100ms cancellation threshold.
	for i := 0; i < 30; i++ {
		input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
		w.queue <- common.Cmd2Value{Ctx: ctx, Cmd: "external-update"}
	}
	select {
	case <-w.completed:
	case <-time.After(900 * time.Millisecond):
		t.Fatal("busy ingress starved bounded metadata")
	}
	deadline := time.Now().Add(time.Second)
	for live.Load() != 30 || w.updates.Load() != 30 {
		if time.Now().After(deadline) {
			t.Fatalf("updates lost: live=%d conversation=%d", live.Load(), w.updates.Load())
		}
		time.Sleep(time.Millisecond)
	}
}

func TestBoundedMetadataCannotRenewAllowanceOrBlockLogout(t *testing.T) {
	for _, logout := range []bool{false, true} {
		t.Run(map[bool]string{false: "live-deadline", true: "logout"}[logout], func(t *testing.T) {
			ctx, cancel := context.WithCancel(recoveryContext(t))
			input := make(chan common.Cmd2Value, 10)
			started, live, done := make(chan struct{}, 10), make(chan struct{}, 10), make(chan struct{})
			go func() {
				defer close(done)
				runMessageSyncLoop(ctx, input, func(c common.Cmd2Value) {
					if c.Cmd != cmdSyncAuxiliaryMetadata {
						live <- struct{}{}
						return
					}
					finish := common.BeginMetadataBatch(c.Ctx)
					defer finish()
					started <- struct{}{}
					for {
						select {
						case <-c.Ctx.Done():
							return
						case <-time.After(20 * time.Millisecond):
							f := common.BeginMetadataBatch(c.Ctx)
							f()
						}
					}
				})
			}()
			defer func() { cancel(); <-done }()
			input <- common.Cmd2Value{Ctx: ctx, Cmd: cmdSyncAuxiliaryMetadata}
			select {
			case <-started:
			case <-time.After(time.Second):
				t.Fatal("not started")
			}
			if logout {
				cancel()
				select {
				case <-done:
				case <-time.After(300 * time.Millisecond):
					t.Fatal("logout waited for batch")
				}
				return
			}
			input <- common.Cmd2Value{Ctx: ctx, Cmd: constant.CmdPushMsg}
			select {
			case <-live:
			case <-time.After(1500 * time.Millisecond):
				t.Fatal("batch renewal starved live message")
			}
		})
	}
}
