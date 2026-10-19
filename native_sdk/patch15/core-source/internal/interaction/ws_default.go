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

//go:build !js

package interaction

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

type Default struct {
	ConnType  int
	conn      *websocket.Conn
	isSetConf bool
}

func transportCloseCode(err error) (int, bool) {
	var closed *websocket.CloseError
	if !errors.As(err, &closed) {
		return 0, false
	}
	// 1006 and 1005 are local sentinels, never a received close code.
	return closed.Code, closed.Code != 1006 && closed.Code != 1005 && closed.Code != 1015
}

func (d *Default) SetReadDeadline(timeout time.Duration) error {
	return d.conn.SetReadDeadline(time.Now().Add(timeout))
}

func (d *Default) SetWriteDeadline(timeout time.Duration) error {
	return d.conn.SetWriteDeadline(time.Now().Add(timeout))
}

func (d *Default) SetReadLimit(limit int64) {
	d.conn.SetReadLimit(limit)

}

func (d *Default) SetPingHandler(handler PingPongHandler) {
	d.conn.SetPingHandler(handler)
}

func (d *Default) SetPongHandler(handler PingPongHandler) {
	d.conn.SetPongHandler(handler)
}

func (d *Default) LocalAddr() string {
	return d.conn.LocalAddr().String()
}

func NewWebSocket(connType int) *Default {
	return &Default{ConnType: connType}
}
func (d *Default) Close() error {
	return d.conn.Close()
}

func (d *Default) WriteMessage(messageType int, message []byte) error {
	return d.conn.WriteMessage(messageType, message)
}

func (d *Default) ReadMessage() (int, []byte, error) {
	return d.conn.ReadMessage()
}

func (d *Default) Dial(urlStr string, requestHeader http.Header) (*http.Response, error) {
	return d.DialContext(context.Background(), urlStr, requestHeader)
}

func (d *Default) DialContext(ctx context.Context, urlStr string, requestHeader http.Header) (*http.Response, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	conn, httpResp, err := websocket.DefaultDialer.DialContext(ctx, urlStr, requestHeader)
	if err == nil {
		d.conn = conn
	}
	return httpResp, err

}

func (d *Default) IsNil() bool {
	if d.conn != nil {
		return false
	}
	return true
}
