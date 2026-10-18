package common

import (
	"context"
	"sync"
	"testing"
	"time"
)

// A foreground group query owns the metadata lock and publishes more profile
// notifications than fit in the queue. The cancelled sync must acquire that
// lock before it can return, exactly as SyncAllJoinedGroupsAndMembersWithLock.
type lockWaitingWorker struct {
	queue     chan Cmd2Value
	lock      sync.Mutex
	started   chan struct{}
	cancelled chan struct{}
	applied   chan string
}

func (w *lockWaitingWorker) GetCh() chan Cmd2Value                   { return w.queue }
func (w *lockWaitingWorker) InterruptibleCommand(cmd Cmd2Value) bool { return cmd.Cmd == "sync" }
func (w *lockWaitingWorker) Work(cmd Cmd2Value) {
	if cmd.Cmd != "sync" {
		w.applied <- cmd.Cmd
		return
	}
	close(w.started)
	<-cmd.Ctx.Done()
	close(w.cancelled)
	w.lock.Lock()
	w.lock.Unlock()
	cmd.Receipt <- cmd.Ctx.Err()
}

func TestCancelledSyncDrainsNotificationsWhileJoiningLockWaiter(t *testing.T) {
	t.Run("small queue", func(t *testing.T) { testCancelledSyncDrains(t, 2) })
	t.Run("production queue", func(t *testing.T) { testCancelledSyncDrains(t, 1000) })
}

func testCancelledSyncDrains(t *testing.T, capacity int) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	count := capacity + 5
	w := &lockWaitingWorker{queue: make(chan Cmd2Value, capacity), started: make(chan struct{}), cancelled: make(chan struct{}), applied: make(chan string, count+1)}
	w.lock.Lock()
	done := make(chan struct{})
	go func() { defer close(done); DoListener(ctx, w) }()
	receipt := make(chan error, 1)
	w.queue <- Cmd2Value{Ctx: ctx, Cmd: "sync", Receipt: receipt}
	<-w.started
	w.queue <- Cmd2Value{Ctx: ctx, Cmd: "live"}
	<-w.cancelled
	// Allow cleanup even against the broken listener, without leaving goroutines.
	producerCtx, stopProducer := context.WithTimeout(ctx, time.Second)
	defer stopProducer()
	produced := make(chan bool, 1)
	go func() {
		defer w.lock.Unlock()
		for i := 0; i < count; i++ {
			select {
			case w.queue <- Cmd2Value{Ctx: ctx, Cmd: "profile"}:
			case <-producerCtx.Done():
				produced <- false
				return
			}
		}
		produced <- true
	}()
	ok := <-produced
	if !ok {
		cancel()
		<-done
		t.Fatal("cancel join stopped draining: group lock/queue cycle")
	}
	select {
	case err := <-receipt:
		if err != context.Canceled {
			t.Errorf("cancelled sync receipt = %v", err)
		}
	case <-time.After(time.Second):
		t.Error("sync failed to exit")
	}
	for i := 0; i < count+1; i++ {
		select {
		case got := <-w.applied:
			want := "profile"
			if i == 0 {
				want = "live"
			}
			if got != want {
				t.Errorf("update %d = %s, want %s", i, got, want)
			}
		case <-time.After(time.Second):
			t.Error("notification lost")
		}
	}
	cancel()
	<-done
}
