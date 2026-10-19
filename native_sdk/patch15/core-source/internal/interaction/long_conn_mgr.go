// Copyright © 2023 OpenIM SDK. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package interaction

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang/protobuf/proto"
	"github.com/gorilla/websocket"
	"github.com/openimsdk/tools/mcontext"

	"github.com/openimsdk/openim-sdk-core/v3/open_im_sdk_callback"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"

	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/log"
)

const (
	// Time allowed to write a message to the peer.
	writeWait = 10 * time.Second

	// Time allowed to read the next pong message from the peer.
	pongWait = 30 * time.Second

	// Send pings to peer with this period. Must be less than pongWait.
	pingPeriod = (pongWait * 8) / 10

	// Maximum message size allowed from peer.
	maxMessageSize = 1024 * 1024

	//Maximum number of reconnection attempts
	maxReconnectAttempts = 300

	sendAndWaitTime  = time.Second * 10
	sendChainMaxWait = 3 * time.Second
	requestBudget    = 30 * time.Second
)

const (
	DefaultNotConnect = iota
	Closed            = iota + 1
	Connecting
	Connected
)

var (
	ErrChanClosed                = errors.New("send channel closed")
	ErrConnClosed                = errors.New("conn has closed")
	ErrNotSupportMessageProtocol = errors.New("not support message protocol")
	ErrClientClosed              = errors.New("client actively close the connection")
	ErrPanic                     = errors.New("panic error")
)

type LongConnMgr struct {
	historyPriority historyPriority
	metrics         connectionTelemetry
	runOnce         sync.Once
	recoveryMu      sync.Mutex
	recoveryWake    chan struct{}
	//conn status mutex
	w          sync.Mutex
	connStatus int
	// Closed when the socket that accepted a request is retired. Guarded by w.
	connectionDone  chan struct{}
	probeContext    context.Context  // immutable session lifetime, unlike diagnostic ctx
	foregroundProbe *foregroundProbe // guarded by mutex
	// The long connection,can be set tcp or websocket.
	conn       LongConn
	listener   open_im_sdk_callback.OnConnListener
	userOnline func(map[string][]int32)
	// Buffered channel of outbound messages.
	send               chan Message
	pushMsgAndMaxSeqCh chan common.Cmd2Value
	conversationCh     chan common.Cmd2Value
	loginMgrCh         chan common.Cmd2Value
	closedErr          error
	ctx                context.Context
	IsCompression      bool
	Syncer             *WsRespAsyn
	encoder            Encoder
	compressor         Compressor
	reconnectStrategy  ReconnectStrategy

	mutex        sync.Mutex
	IsBackground bool
	// write conn lock
	connWrite *sync.Mutex

	sub *subscription

	mb *MessageBatcher
}

type Message struct {
	Ctx     context.Context `json:"-"`
	Message GeneralWsReq
	Resp    chan *GeneralWsResp
	Order   *ccontext.SendOrderInfo
}

type laneState struct {
	laneType ccontext.SendOrderLane
	expected int64
	pending  map[int64]Message
	timer    *time.Timer
	active   bool
}

func newLaneState(lane ccontext.SendOrderLane) *laneState {
	return &laneState{
		laneType: lane,
		expected: 1,
		pending:  make(map[int64]Message),
	}
}

func NewLongConnMgr(ctx context.Context, listener open_im_sdk_callback.OnConnListener, userOnline func(map[string][]int32), pushMsgAndMaxSeqCh, loginMgrCh chan common.Cmd2Value) *LongConnMgr {
	l := &LongConnMgr{
		listener:           listener,
		userOnline:         userOnline,
		pushMsgAndMaxSeqCh: pushMsgAndMaxSeqCh,
		loginMgrCh:         loginMgrCh,
		IsCompression:      true,
		Syncer:             NewWsRespAsyn(),
		encoder:            NewGobEncoder(),
		compressor:         NewGzipCompressor(),
		reconnectStrategy:  NewExponentialRetry(),
		sub:                newSubscription(),
	}
	l.send = make(chan Message, 10)
	l.conn = NewWebSocket(WebSocket)
	l.connWrite = new(sync.Mutex)
	l.ctx = ctx
	l.probeContext = ctx
	l.mb = NewMessageBatcher(l.doBatch)
	return l
}

func (c *LongConnMgr) RegisterSendOrder(lane ccontext.SendOrderLane, seq int64, deadline time.Time) {
	// no-op after simplification
}

func (c *LongConnMgr) Run(ctx context.Context) {
	c.runOnce.Do(func() {
		ctx, cancel := context.WithCancel(ctx)
		go func() { defer cancel(); c.readPump(ctx) }()
		go c.writePump(ctx)
		go c.heartbeat(ctx)
		go func() {
			<-ctx.Done()
			// DialContext releases this lock on cancellation. Closing the socket
			// releases a blocked reader without waiting for its read deadline.
			c.connWrite.Lock()
			defer c.connWrite.Unlock()
			if !c.conn.IsNil() {
				_ = c.conn.Close()
			}
		}()
	})
}

func (c *LongConnMgr) SendReqWaitResp(ctx context.Context, m proto.Message, reqIdentifier int, resp proto.Message) error {
	ctx, cancel := context.WithTimeout(ctx, requestBudget)
	defer cancel()
	if ctx.Err() != nil {
		return sdkerrs.ErrCtxDeadline
	}
	data, err := proto.Marshal(m)
	if err != nil {
		return sdkerrs.ErrArgs
	}
	orderInfo, _ := ccontext.GetSendOrderInfo(ctx)
	msg := Message{
		Ctx: ctx,
		Message: GeneralWsReq{
			ReqIdentifier: reqIdentifier,
			SendID:        ccontext.Info(ctx).UserID(),
			OperationID:   ccontext.Info(ctx).OperationID(),
			Data:          data,
		},
		Resp:  make(chan *GeneralWsResp, 1),
		Order: orderInfo,
	}
	select {
	case c.send <- msg:
	case <-ctx.Done():
		return sdkerrs.ErrCtxDeadline
	}
	log.ZDebug(ctx, "send message to send channel success", "msg", m, "reqIdentifier", reqIdentifier)
	select {
	case <-ctx.Done():
		return sdkerrs.ErrCtxDeadline
	case v, ok := <-msg.Resp:
		if !ok {
			return errors.New("response channel closed")
		}
		if v.ErrCode != 0 {
			return errs.NewCodeError(v.ErrCode, v.ErrMsg)
		}
		if err := proto.Unmarshal(v.Data, resp); err != nil {
			return sdkerrs.ErrArgs
		}
		return nil
	}
}

// readPump pumps messages from the websocket connection to the hub.
//
// The application runs readPump in a per-connection goroutine. The application
// ensures that there is at most one reader on a connection by executing all
// reads from this goroutine.

func (c *LongConnMgr) readPump(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Sprintf("panic: %+v\n%s", r, debug.Stack())

			log.ZWarn(ctx, "readPump panic", nil, "panic info", err)
		}
	}()

	log.ZDebug(ctx, "readPump start", "goroutine ID:", getGoroutineID())
	defer func() {
		_ = c.close()
		log.ZWarn(c.ctx, "readPump closed", c.closeError())
	}()
	connNum := 0
	for {
		select {
		case <-ctx.Done():
			c.setCloseError(ctx.Err())
			log.ZInfo(c.ctx, "readPump done, sdk logout.....")
			return
		default:
		}
		ctx = ccontext.WithOperationID(ctx, utils.OperationIDGenerator())
		needRecon, err := c.reConn(ctx, &connNum)
		if !needRecon {
			c.setCloseError(err)
			return
		}
		if err != nil {
			log.ZWarn(c.ctx, "reConn", err)
			if !c.waitReconnect(ctx, c.reconnectStrategy.GetSleepInterval()) {
				return
			}
			continue
		}
		c.conn.SetReadLimit(maxMessageSize)
		_ = c.conn.SetReadDeadline(pongWait)
		messageType, message, err := c.conn.ReadMessage()
		if err != nil {
			c.setCloseError(err)
			log.ZError(c.ctx, "readMessage err", err, "goroutine ID:", getGoroutineID())
			_ = c.close()
			c.sub.onConnClosed(err)
			continue
		}
		c.metrics.lastMessage.Store(time.Now().UnixMilli())
		switch messageType {
		case MessageBinary:
			err := c.handleMessage(message)
			if err != nil {
				c.setCloseError(err)
				_ = c.close()
				if !c.waitReconnect(ctx, time.Second) {
					return
				}
				continue
			}
		case MessageText:
			c.setCloseError(ErrNotSupportMessageProtocol)
			_ = c.close()
			if !c.waitReconnect(ctx, time.Second) {
				return
			}
			continue
		case CloseMessage:
			c.setCloseError(ErrClientClosed)
			_ = c.close()
			continue
		default:
		}
	}
}

// writePump pumps messages from the hub to the websocket connection.
//
// A goroutine running writePump is started for each connection. The
// application ensures that there is at most one writer to a connection by
// executing all writes from this goroutine.
func (c *LongConnMgr) writePump(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Sprintf("panic: %+v\n%s", r, debug.Stack())

			log.ZWarn(ctx, "writePump panic", nil, "panic info", err)
		}
	}()

	log.ZDebug(ctx, "writePump start", "goroutine ID:", getGoroutineID())

	defer func() {
		c.close()
		close(c.send)
	}()
	textLane := newLaneState(ccontext.SendOrderLaneText)
	mediaLane := newLaneState(ccontext.SendOrderLaneMedia)
	for {
		var textTimer <-chan time.Time
		if textLane.active && textLane.timer != nil {
			textTimer = textLane.timer.C
		}
		var mediaTimer <-chan time.Time
		if mediaLane.active && mediaLane.timer != nil {
			mediaTimer = mediaLane.timer.C
		}
		select {
		case <-ctx.Done():
			c.setCloseError(ctx.Err())
			log.ZInfo(c.ctx, "writePump done, sdk logout.....")
			return
		case message, ok := <-c.send:
			if !ok {
				// The hub closed the channel.
				_ = c.conn.SetWriteDeadline(writeWait)
				err := c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				if err != nil {
					log.ZError(c.ctx, "send close message error", err)
				}
				c.setCloseError(ErrChanClosed)
				return
			}
			c.processIncomingMessage(textLane, mediaLane, message)
		case <-textTimer:
			c.handleLaneTimeout(textLane)
		case <-mediaTimer:
			c.handleLaneTimeout(mediaLane)
		}
	}
}

func (c *LongConnMgr) processIncomingMessage(textLane, mediaLane *laneState, message Message) {
	if message.Order == nil || !message.Order.Ordered {
		c.dispatchMessage(message)
		return
	}
	lane := laneByType(message.Order.Lane, textLane, mediaLane)
	if lane == nil {
		c.dispatchMessage(message)
		return
	}
	if message.Order.Seq < lane.expected {
		c.dispatchMessage(message)
		return
	}
	if message.Order.Seq == lane.expected {
		lane.stopTimer()
		c.dispatchMessage(message)
		lane.expected++
		c.flushLane(lane)
		return
	}
	lane.pending[message.Order.Seq] = message
	if lane.hasGap() {
		lane.startTimer()
	}
}

func (c *LongConnMgr) handleLaneTimeout(lane *laneState) {
	if lane == nil {
		return
	}
	lane.stopTimer()
	lane.expected++
	for !c.flushLane(lane) {
		lane.expected++
		log.ZDebug(c.ctx, "not flushed, add expected seq")
	}
}

func (c *LongConnMgr) flushLane(lane *laneState) bool {
	var flushed bool
	for {
		msg, ok := lane.pending[lane.expected]
		if !ok {
			break
		}
		flushed = true
		delete(lane.pending, lane.expected)
		lane.stopTimer()
		c.dispatchMessage(msg)
		lane.expected++
	}
	if lane.hasGap() {
		lane.startTimer()
	} else {
		lane.stopTimer()
		flushed = true // prevent dead loop
	}
	return flushed
}

func laneByType(laneType ccontext.SendOrderLane, textLane, mediaLane *laneState) *laneState {
	switch laneType {
	case ccontext.SendOrderLaneText:
		return textLane
	case ccontext.SendOrderLaneMedia:
		return mediaLane
	default:
		return nil
	}
}

func (c *LongConnMgr) dispatchMessage(message Message) {
	log.ZDebug(c.ctx, "writePump recv message", "reqIdentifier", message.Message.ReqIdentifier,
		"operationID", message.Message.OperationID, "sendID", message.Message.SendID)
	ctx := message.Ctx
	if ctx == nil {
		ctx = c.ctx
	}
	resp, err := c.sendAndWaitResp(ctx, &message.Message)
	if err != nil {
		resp = &GeneralWsResp{
			ReqIdentifier: message.Message.ReqIdentifier,
			OperationID:   message.Message.OperationID,
			Data:          nil,
		}
		if code, ok := errs.Unwrap(err).(errs.CodeError); ok {
			resp.ErrCode = code.Code()
			resp.ErrMsg = code.Msg()
		} else {
			log.ZError(c.ctx, "writeBinaryMsgAndRetry failed", err, "wsReq", message.Message)
		}

	}
	if nErr := c.Syncer.notifyCh(message.Resp, resp, 1); nErr != nil {
		log.ZError(c.ctx, "TriggerCmdNewMsgCome failed", nErr, "wsResp", resp)
	}
}

func (c *LongConnMgr) heartbeat(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Sprintf("panic: %+v\n%s", r, debug.Stack())

			log.ZWarn(ctx, "heartbeat panic", nil, "panic info", err)
		}
	}()

	log.ZDebug(ctx, "heartbeat start", "goroutine ID:", getGoroutineID())
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		log.ZWarn(c.ctx, "heartbeat closed", nil, "heartbeat", "heartbeat done sdk logout.....")
	}()
	for {
		select {
		case <-ctx.Done():
			log.ZInfo(ctx, "heartbeat done sdk logout.....")
			return
		case <-ticker.C:
			log.ZInfo(ctx, "sendPingMessage", "goroutine ID:", getGoroutineID())
			c.sendPingMessage(ctx)
		}
	}

}

func (c *LongConnMgr) sendPingMessage(ctx context.Context) {
	c.connWrite.Lock()
	defer c.connWrite.Unlock()
	opid := utils.OperationIDGenerator()
	log.ZDebug(ctx, "ping Message Started", "goroutine ID:", getGoroutineID(), "opid", opid)
	if c.IsConnected() {
		log.ZDebug(ctx, "ping Message Started isConnected", "goroutine ID:", getGoroutineID(), "opid", opid)
		c.conn.SetWriteDeadline(writeWait)
		if err := c.conn.WriteMessage(PingMessage, []byte(opid)); err != nil {
			log.ZWarn(ctx, "ping Message failed", err, "goroutine ID:", getGoroutineID(), "opid", opid)
			return
		}
		c.metrics.lastPing.Store(time.Now().UnixMilli())
	} else {
		log.ZDebug(ctx, "ping Message failed, connection", "connStatus", c.GetConnectionStatus(), "goroutine ID:", getGoroutineID(), "opid", opid)
	}
}

func (l *laneState) stopTimer() {
	if l.timer == nil {
		return
	}
	if !l.timer.Stop() {
		select {
		case <-l.timer.C:
		default:
		}
	}
	l.active = false
}

func (l *laneState) startTimer() {
	if l.active {
		return
	}
	delay := sendChainMaxWait
	if l.timer == nil {
		l.timer = time.NewTimer(delay)
	} else {
		if !l.timer.Stop() {
			select {
			case <-l.timer.C:
			default:
			}
		}
		l.timer.Reset(delay)
	}
	l.active = true
}

func (l *laneState) hasGap() bool {
	if len(l.pending) == 0 {
		return false
	}
	if _, ok := l.pending[l.expected]; ok {
		return false
	}
	return true
}

func getGoroutineID() int64 {
	buf := make([]byte, 64)
	buf = buf[:runtime.Stack(buf, false)]
	idField := strings.Fields(strings.TrimPrefix(string(buf), "goroutine "))[0]
	id, err := strconv.ParseInt(idField, 10, 64)
	if err != nil {
		return 0
	}
	return id
}

func (c *LongConnMgr) sendAndWaitResp(ctx context.Context, msg *GeneralWsReq) (*GeneralWsResp, error) {
	tempChan, connectionDone, err := c.writeBinaryMsgAndRetry(ctx, msg)
	defer c.Syncer.DelCh(msg.MsgIncr)
	if err != nil {
		return nil, err
	} else {
		select {
		case <-ctx.Done():
			return nil, sdkerrs.ErrCtxDeadline
		case resp := <-tempChan:
			return resp, nil
		case <-connectionDone:
			// An ACK already routed before closure is still authoritative. Do not
			// turn an acknowledged send into a failure merely because both are ready.
			select {
			case resp := <-tempChan:
				return resp, nil
			default:
				return nil, sdkerrs.ErrNetwork.WrapMsg("request connection closed")
			}
		case <-time.After(sendAndWaitTime):
			return nil, sdkerrs.ErrNetworkTimeOut
		}

	}
}

func (c *LongConnMgr) writeBinaryMsgAndRetry(ctx context.Context, msg *GeneralWsReq) (chan *GeneralWsResp, <-chan struct{}, error) {
	msgIncr, tempChan := c.Syncer.AddCh(msg.SendID)
	msg.MsgIncr = msgIncr
	if c.GetConnectionStatus() != Connected && msg.ReqIdentifier == constant.GetNewestSeq {
		return tempChan, nil, sdkerrs.ErrNetwork.WrapMsg("connection closed,conning...")
	}
	for i := 0; i < maxReconnectAttempts; i++ {
		if ctx.Err() != nil {
			return tempChan, nil, sdkerrs.ErrCtxDeadline
		}
		c.connWrite.Lock()
		// Capture before writing, under the same lock that excludes redial.
		// Looking up the current socket after the write can miss a fast reconnect.
		connectionDone := c.requestConnectionDone()
		var err error
		if ctx.Err() != nil {
			err = sdkerrs.ErrCtxDeadline
		} else {
			budget := writeWait
			if deadline, ok := ctx.Deadline(); ok && time.Until(deadline) < budget {
				budget = time.Until(deadline)
			}
			err = c.writeBinaryMsgWithBudget(*msg, budget)
		}
		c.connWrite.Unlock()
		if errors.Is(err, sdkerrs.ErrCtxDeadline) {
			return tempChan, nil, err
		}
		if err != nil {
			log.ZError(c.ctx, "send binary message error", err, "message", msg)
			c.setCloseError(err)
			_ = c.close()
			timer := time.NewTimer(time.Second)
			select {
			case <-ctx.Done():
				timer.Stop()
				return tempChan, nil, sdkerrs.ErrCtxDeadline
			case <-timer.C:
			}
			continue
		} else {
			return tempChan, connectionDone, nil
		}
	}
	return nil, nil, sdkerrs.ErrNetwork.WrapMsg("send binary message error")
}

func (c *LongConnMgr) writeBinaryMsgAndNotRetry(msg *GeneralWsReq) (chan *GeneralWsResp, error) {
	msgIncr, tempChan := c.Syncer.AddCh(msg.SendID)
	msg.MsgIncr = msgIncr
	if err := c.writeBinaryMsg(*msg); err != nil {
		c.Syncer.DelCh(msgIncr)
		return nil, err
	}
	return tempChan, nil
}

func (c *LongConnMgr) writeBinaryMsg(req GeneralWsReq) error {
	c.connWrite.Lock()
	defer c.connWrite.Unlock()
	return c.writeBinaryMsgNoLock(req)
}

func (c *LongConnMgr) writeSubInfo(subscribeUserID, unsubscribeUserID []string, lock bool) error {
	opID := utils.OperationIDGenerator()
	sCtx := ccontext.WithOperationID(c.ctx, opID)
	log.ZInfo(sCtx, "writeSubInfo start", "goroutine ID:", getGoroutineID())
	subReq := sdkws.SubUserOnlineStatus{
		SubscribeUserID:   subscribeUserID,
		UnsubscribeUserID: unsubscribeUserID,
	}
	data, err := proto.Marshal(&subReq)
	if err != nil {
		log.ZError(sCtx, "proto.Marshal", err)
		return err
	}
	req := GeneralWsReq{
		ReqIdentifier: constant.WsSubUserOnlineStatus,
		SendID:        ccontext.Info(sCtx).UserID(),
		OperationID:   opID,
		MsgIncr:       utils.OperationIDGenerator(),
		Data:          data,
	}
	if lock {
		return c.writeBinaryMsg(req)
	} else {
		return c.writeBinaryMsgNoLock(req)
	}
}

func (c *LongConnMgr) writeBinaryMsgNoLock(req GeneralWsReq) error {
	return c.writeBinaryMsgWithBudget(req, writeWait)
}

func (c *LongConnMgr) writeBinaryMsgWithBudget(req GeneralWsReq, budget time.Duration) error {
	encodeBuf, err := c.encoder.Encode(req)
	if err != nil {
		return err
	}
	if c.GetConnectionStatus() != Connected {
		return sdkerrs.ErrNetwork.WrapMsg("connection closed,re conning...")
	}
	if budget <= 0 {
		return sdkerrs.ErrCtxDeadline
	}
	_ = c.conn.SetWriteDeadline(budget)
	if c.IsCompression {
		resultBuf, compressErr := c.compressor.CompressWithPool(encodeBuf)
		if compressErr != nil {
			return compressErr
		}
		return c.conn.WriteMessage(MessageBinary, resultBuf)
	} else {
		return c.conn.WriteMessage(MessageBinary, encodeBuf)
	}
}

func (c *LongConnMgr) close() error {
	c.w.Lock()
	defer c.w.Unlock()
	if c.connStatus == Closed || c.connStatus == Connecting || c.connStatus == DefaultNotConnect {
		return nil
	}
	c.connStatus = Closed
	c.endConnectionRequestsLocked()
	log.ZWarn(c.ctx, "conn closed", c.closeError())
	c.metrics.disconnected(c.ctx, c.closeError(), c.GetBackground())
	return c.conn.Close()
}

func (c *LongConnMgr) handleMessage(message []byte) error {
	if c.IsCompression {
		var decompressErr error
		message, decompressErr = c.compressor.DecompressWithPool(message)
		if decompressErr != nil {
			log.ZError(c.ctx, "DeCompress failed", decompressErr, message)
			return sdkerrs.ErrMsgDeCompression
		}
	}
	var wsResp GeneralWsResp
	err := c.encoder.Decode(message, &wsResp)
	if err != nil {
		log.ZError(c.ctx, "decodeBinaryWs err", err, "message", message)
		return sdkerrs.ErrMsgDecodeBinaryWs
	}
	ctx := context.WithValue(c.ctx, "operationID", wsResp.OperationID)
	log.ZInfo(ctx, "recv msg", "errCode", wsResp.ErrCode, "errMsg", wsResp.ErrMsg,
		"reqIdentifier", wsResp.ReqIdentifier)
	switch wsResp.ReqIdentifier {
	case constant.PushMsg:
		if err = c.doPushMsg(ctx, wsResp); err != nil {
			log.ZError(ctx, "doWSPushMsg failed", err, "wsResp", wsResp)
		}
	case constant.LogoutMsg:
		if err := c.Syncer.NotifyResp(ctx, wsResp); err != nil {
			log.ZError(ctx, "notifyResp failed", err, "wsResp", wsResp)
		}
		c.mb.Close()
		return sdkerrs.ErrLoginOut
	case constant.KickOnlineMsg:
		log.ZDebug(ctx, "socket receive client kicked offline")
		c.mb.Close()
		err = errs.ErrTokenKicked.WrapMsg("socket receive client kicked offline")
		ccontext.GetApiErrCodeCallback(ctx).OnError(ctx, err)
		return err
	case constant.GetNewestSeq:
		fallthrough
	case constant.PullMsgByRange:
		fallthrough
	case constant.PullMsgBySeqList:
		fallthrough
	case constant.GetConvMaxReadSeq:
		fallthrough
	case constant.PullConvLastMessage:
		fallthrough
	case constant.SendMsg:
		fallthrough
	case constant.SendSignalMsg:
		fallthrough
	case constant.SetBackgroundStatus:
		if err := c.Syncer.NotifyResp(ctx, wsResp); err != nil {
			log.ZError(ctx, "notifyResp failed", err, "reqIdentifier", wsResp.ReqIdentifier, "errCode",
				wsResp.ErrCode, "errMsg", wsResp.ErrMsg, "msgIncr", wsResp.MsgIncr, "operationID", wsResp.OperationID)
		}
	case constant.WsSubUserOnlineStatus:
		if err := c.handlerUserOnlineChange(ctx, wsResp); err != nil {
			log.ZError(ctx, "handlerUserOnlineChange failed", err, "wsResp", wsResp)
		}
	default:
		return sdkerrs.ErrMsgBinaryTypeNotSupport
	}
	return nil
}

func (c *LongConnMgr) handlerUserOnlineChange(ctx context.Context, wsResp GeneralWsResp) error {
	if wsResp.ErrCode != 0 {
		return errs.New("handlerUserOnlineChange failed")
	}
	var tips sdkws.SubUserOnlineStatusTips
	if err := proto.Unmarshal(wsResp.Data, &tips); err != nil {
		return err
	}
	log.ZDebug(ctx, "handlerUserOnlineChange", "tips", &tips)
	c.callbackUserOnlineChange(c.sub.setUserState(tips.Subscribers))
	return nil
}

func (c *LongConnMgr) GetUserOnlinePlatformIDs(ctx context.Context, userIDs []string) (map[string][]int32, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Second*5)
	defer cancel()
	exist, wait, subUserIDs, unsubUserIDs := c.sub.getUserOnline(userIDs)
	if len(subUserIDs)+len(unsubUserIDs) > 0 {
		if err := c.writeSubInfo(subUserIDs, unsubUserIDs, true); err != nil {
			c.sub.writeFailed(wait, err)
			return nil, err
		}
	}
	for userID, statues := range wait {
		select {
		case <-ctx.Done():
			return nil, context.Cause(ctx)
		case <-statues.Done():
			online, err := statues.Result()
			if err != nil {
				return nil, err
			}
			exist[userID] = online
		}
	}
	return exist, nil
}

func (c *LongConnMgr) UnsubscribeUserOnlinePlatformIDs(ctx context.Context, userIDs []string) error {
	if len(userIDs) > 0 {
		c.sub.unsubscribe(userIDs)
	}
	return nil
}

func (c *LongConnMgr) writeConnFirstSubMsg(ctx context.Context) error {
	userIDs := c.sub.getNewConnSubUserIDs()
	log.ZDebug(ctx, "writeConnFirstSubMsg getNewConnSubUserIDs", "userIDs", userIDs)
	if len(userIDs) == 0 {
		return nil
	}
	if err := c.writeSubInfo(userIDs, nil, false); err != nil {
		c.sub.onConnClosed(err)
		return err
	}
	return nil
}

func (c *LongConnMgr) callbackUserOnlineChange(users map[string][]int32) {
	log.ZDebug(c.ctx, "#### ===> callbackUserOnlineChange", "users", users)
	if len(users) == 0 {
		return
	}
	c.userOnline(users)
	//for userID, onlinePlatformIDs := range users {
	//	status := userPb.OnlineStatus{
	//		UserID:      userID,
	//		PlatformIDs: onlinePlatformIDs,
	//	}
	//	if len(status.PlatformIDs) == 0 {
	//		status.Status = constant.Offline
	//	} else {
	//		status.Status = constant.Online
	//	}
	//	c.userOnline.OnUserStatusChanged(utils.StructToJsonString(users))
	//}
}

func (c *LongConnMgr) IsConnected() bool {
	c.w.Lock()
	defer c.w.Unlock()
	if c.connStatus == Connected {
		return true
	}
	return false

}
func (c *LongConnMgr) GetConnectionStatus() int {
	c.w.Lock()
	defer c.w.Unlock()
	return c.connStatus
}

func (c *LongConnMgr) SetConnectionStatus(status int) {
	c.w.Lock()
	defer c.w.Unlock()
	if status == Connected && c.connStatus != Connected {
		c.endConnectionRequestsLocked()
		c.connectionDone = make(chan struct{})
	} else if status != Connected {
		c.endConnectionRequestsLocked()
	}
	c.connStatus = status
}

func (c *LongConnMgr) reConn(ctx context.Context, num *int) (needRecon bool, err error) {
	if c.IsConnected() {
		return true, nil
	}
	c.connWrite.Lock()
	defer c.connWrite.Unlock()
	c.listener.OnConnecting()
	c.SetConnectionStatus(Connecting)
	url := fmt.Sprintf("%s?sendID=%s&token=%s&platformID=%d&operationID=%s&isBackground=%t",
		ccontext.Info(ctx).WsAddr(), ccontext.Info(ctx).UserID(), ccontext.Info(ctx).Token(),
		ccontext.Info(ctx).PlatformID(), ccontext.Info(ctx).OperationID(), c.GetBackground())
	if c.IsCompression {
		url += fmt.Sprintf("&compression=%s", "gzip")
	}
	log.ZDebug(ctx, "conn start", "endpoint", ccontext.Info(ctx).WsAddr(), "background", c.GetBackground())
	c.metrics.attempts.Add(1)
	resp, err := dialSession(ctx, c.conn, url)
	if ctx.Err() != nil {
		if err == nil {
			_ = c.conn.Close()
		}
		c.SetConnectionStatus(Closed)
		return false, ctx.Err()
	}
	if err != nil {
		c.SetConnectionStatus(Closed)
		if resp != nil {
			defer resp.Body.Close()
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				return true, err
			}
			log.ZInfo(ctx, "reConn resp", "body", string(body))
			var apiResp struct {
				ErrCode int    `json:"errCode"`
				ErrMsg  string `json:"errMsg"`
				ErrDlt  string `json:"errDlt"`
			}
			if err := json.Unmarshal(body, &apiResp); err != nil {
				return true, err
			}
			err = errs.NewCodeError(apiResp.ErrCode, apiResp.ErrMsg).WithDetail(apiResp.ErrDlt).Wrap()
			ccontext.GetApiErrCodeCallback(ctx).OnError(ctx, err)
			switch apiResp.ErrCode {
			case
				errs.TokenExpiredError,
				errs.TokenInvalidError,
				errs.TokenMalformedError,
				errs.TokenNotValidYetError,
				errs.TokenUnknownError,
				errs.TokenNotExistError,
				errs.TokenKickedError:
				return false, err
			default:
				return true, err
			}
		}
		c.listener.OnConnectFailed(sdkerrs.NetworkError, err.Error())
		return true, err
	}
	if err := c.writeConnFirstSubMsg(ctx); err != nil {
		log.ZError(ctx, "first write user online sub info error", err)
		ccontext.GetApiErrCodeCallback(ctx).OnError(ctx, err)
		c.listener.OnConnectFailed(sdkerrs.NetworkError, err.Error())
		c.conn.Close()
		c.SetConnectionStatus(Closed)
		return true, err
	}
	if ctx.Err() != nil {
		_ = c.conn.Close()
		c.SetConnectionStatus(Closed)
		return false, ctx.Err()
	}
	c.setCloseError(nil)
	c.metrics.connected(ctx, c.GetBackground())
	c.listener.OnConnectSuccess()
	c.sub.onConnSuccess()
	c.ctx = newContext(c.conn.LocalAddr())
	c.ctx = context.WithValue(ctx, "ConnContext", c.ctx)
	c.SetConnectionStatus(Connected)
	c.conn.SetPongHandler(c.pongHandler)
	c.conn.SetPingHandler(c.pingHandler)
	*num++
	log.ZInfo(c.ctx, "long conn establish success", "localAddr", c.conn.LocalAddr(), "connNum", *num)
	c.reconnectStrategy.Reset()
	_ = common.TriggerCmdConnected(ctx, c.pushMsgAndMaxSeqCh)
	return true, nil
}

func (c *LongConnMgr) doBatch(ctxs []context.Context, msg *sdkws.PushMessages) {
	var ctx context.Context
	switch len(ctxs) {
	case 0:
		return
	case 1:
		ctx = ctxs[0]
	default:
		var buf bytes.Buffer
		buf.WriteString("Batch_")
		for _, v := range ctxs {
			operationID := mcontext.GetOperationID(v)
			if operationID != "" {
				buf.WriteString(operationID)
				buf.WriteString("$")
			}
		}
		data := buf.Bytes()
		data = data[:len(data)-1]
		ctx = mcontext.SetOperationID(ctxs[0], string(data))
	}
	if err := common.TriggerCmdPushMsg(ctx, msg, c.pushMsgAndMaxSeqCh); err != nil {
		log.ZError(ctx, "doBatch DispatchPushMsg", err, "msg", msg)
	}
}

func (c *LongConnMgr) doPushMsg(ctx context.Context, wsResp GeneralWsResp) error {
	var msg sdkws.PushMessages
	err := proto.Unmarshal(wsResp.Data, &msg)
	if err != nil {
		return err
	}
	log.ZDebug(ctx, "recv push msg", "msgNum", len(msg.Msgs), "notificationNum", len(msg.NotificationMsgs), "msg", &msg)
	c.mb.Enqueue(ctx, &msg)
	return nil
}
func (c *LongConnMgr) Close(ctx context.Context) {
	c.wakeReconnect()
	if c.GetConnectionStatus() == Connected {
		log.ZInfo(ctx, "network change conn close")
		c.setCloseError(errors.New("closed by client network change"))
		err := c.close()
		if err != nil {
			log.ZWarn(ctx, "actively close err", err)
		}
	} else {
		log.ZInfo(ctx, "conn already closed")
	}

}
func (c *LongConnMgr) GetBackground() bool {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	return c.IsBackground
}
func (c *LongConnMgr) SetBackground(isBackground bool) {
	c.mutex.Lock()
	changed := c.IsBackground != isBackground
	c.IsBackground = isBackground
	if isBackground {
		c.cancelForegroundProbeLocked()
	}
	c.mutex.Unlock()
	if changed && !isBackground {
		c.wakeReconnect()
	}
	// A lifecycle report may have been coalesced while an earlier server ACK
	// was pending. An explicit foreground report still needs a liveness check.
	if !isBackground {
		c.probeForegroundConnection(foregroundProbeTimeout)
	}
}

// receive ping and send pong.
func (c *LongConnMgr) pingHandler(_ string) error {
	if err := c.conn.SetReadDeadline(pongWait); err != nil {
		return err
	}

	return c.writePongMsg()
}

// when client send pong.
func (c *LongConnMgr) pongHandler(appData string) error {
	c.acknowledgeForegroundProbe(appData)
	c.metrics.lastPong.Store(time.Now().UnixMilli())
	log.ZDebug(c.ctx, "server Pong Message Received", "appData", appData)
	if err := c.conn.SetReadDeadline(pongWait); err != nil {
		return err
	}
	return nil
}

func (c *LongConnMgr) writePongMsg() error {
	c.connWrite.Lock()
	defer c.connWrite.Unlock()

	err := c.conn.SetWriteDeadline(writeWait)
	if err != nil {
		return err
	}

	return c.conn.WriteMessage(PongMessage, nil)
}
