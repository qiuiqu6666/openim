package interaction

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
)

// Only the transport boundary is faked; requests use the real response router.
type lifetimeTransport struct {
	LongConn
	written chan struct{}
	onWrite func()
}

func (c *lifetimeTransport) WriteMessage(int, []byte) error {
	c.written <- struct{}{}
	if c.onWrite != nil {
		c.onWrite()
	}
	return nil
}
func (c *lifetimeTransport) SetWriteDeadline(time.Duration) error { return nil }
func (c *lifetimeTransport) Close() error                         { return nil }

func lifetimeManager(t *testing.T) (*LongConnMgr, *lifetimeTransport) {
	t.Helper()
	transport := &lifetimeTransport{written: make(chan struct{}, 8)}
	c := &LongConnMgr{ctx: recoveryContext(t), conn: transport, connWrite: new(sync.Mutex),
		Syncer: NewWsRespAsyn(), encoder: NewGobEncoder()}
	c.SetConnectionStatus(Connected)
	return c, transport
}

func TestAcknowledgedRequestSurvivesImmediateDisconnect(t *testing.T) {
	c, transport := lifetimeManager(t)
	request := &GeneralWsReq{ReqIdentifier: constant.SendMsg}
	transport.onWrite = func() {
		if err := c.Syncer.NotifyResp(c.ctx, GeneralWsResp{MsgIncr: request.MsgIncr, Data: []byte("ack")}); err != nil {
			t.Fatal(err)
		}
		_ = c.close()
	}
	response, err := c.sendAndWaitResp(c.ctx, request)
	if err != nil || response == nil || string(response.Data) != "ack" {
		t.Fatalf("lost acknowledged send on closure: response=%v error=%v", response, err)
	}
}

func TestForegroundConfirmationRunsAfterDisconnectedQueuedRequest(t *testing.T) {
	c, transport := lifetimeManager(t)
	ctx, cancel := context.WithCancel(c.ctx)
	defer cancel()
	old := Message{Ctx: ctx, Message: GeneralWsReq{ReqIdentifier: constant.PullMsgByRange}, Resp: make(chan *GeneralWsResp, 1)}
	foreground := Message{Ctx: ctx, Message: GeneralWsReq{ReqIdentifier: constant.SetBackgroundStatus}, Resp: make(chan *GeneralWsResp, 1)}
	resume := make(chan struct{})
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		c.dispatchMessage(old)
		<-resume
		c.dispatchMessage(foreground)
	}()
	<-transport.written
	_ = c.close()
	c.SetConnectionStatus(Connected)
	close(resume)
	select {
	case <-transport.written:
	case <-time.After(300 * time.Millisecond):
		cancel()
		<-finished
		t.Fatal("foreground confirmation stayed behind a disconnected history request")
	}
	c.Syncer.wsMutex.RLock()
	var id string
	for key := range c.Syncer.wsNotification {
		id = key
	}
	c.Syncer.wsMutex.RUnlock()
	if id == "" {
		t.Fatal("foreground request missing")
	}
	if err := c.Syncer.NotifyResp(ctx, GeneralWsResp{MsgIncr: id}); err != nil {
		t.Fatal(err)
	}
	<-finished
	if response := <-old.Resp; response.ErrCode == 0 {
		t.Fatal("disconnected request reported success")
	}
	if response := <-foreground.Resp; response.ErrCode != 0 {
		t.Fatalf("foreground confirmation failed: %v", response)
	}
}

func TestDisconnectedRequestReleasesForegroundQueue(t *testing.T) {
	c, transport := lifetimeManager(t)
	ctx, cancel := context.WithCancel(c.ctx)
	defer cancel()
	done := make(chan error, 1)
	go func() {
		_, err := c.sendAndWaitResp(ctx, &GeneralWsReq{ReqIdentifier: constant.SetBackgroundStatus})
		done <- err
	}()
	<-transport.written
	if err := c.close(); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("disconnected request reported success")
		}
	case <-time.After(300 * time.Millisecond):
		cancel()
		<-done
		t.Fatal("old socket request still blocks foreground recovery after disconnect")
	}
	if len(c.Syncer.wsNotification) != 0 {
		t.Fatal("response registration leaked")
	}
}

func TestRecoveredConnectionDoesNotInheritOldRequestWait(t *testing.T) {
	c, transport := lifetimeManager(t)
	ctx, cancel := context.WithCancel(c.ctx)
	defer cancel()
	oldDone := make(chan error, 1)
	go func() {
		_, err := c.sendAndWaitResp(ctx, &GeneralWsReq{ReqIdentifier: constant.SetBackgroundStatus})
		oldDone <- err
	}()
	<-transport.written
	_ = c.close()
	c.SetConnectionStatus(Connected)
	select {
	case err := <-oldDone:
		if err == nil {
			t.Fatal("old request succeeded on replacement connection")
		}
	case <-time.After(300 * time.Millisecond):
		cancel()
		<-oldDone
		t.Fatal("replacement connection hid the old socket closure")
	}
	request := &GeneralWsReq{ReqIdentifier: constant.GetNewestSeq}
	newDone := make(chan error, 1)
	go func() { _, err := c.sendAndWaitResp(ctx, request); newDone <- err }()
	<-transport.written
	select {
	case err := <-newDone:
		t.Fatalf("new request inherited old cancellation: %v", err)
	default:
	}
	if err := c.Syncer.NotifyResp(ctx, GeneralWsResp{MsgIncr: request.MsgIncr}); err != nil {
		t.Fatal(err)
	}
	if err := <-newDone; err != nil {
		t.Fatal(err)
	}
}
