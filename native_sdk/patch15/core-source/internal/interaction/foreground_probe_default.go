//go:build !js

package interaction

import (
	"github.com/gorilla/websocket"
	"time"
)

// Called while the manager guards a Connected socket. WriteControl is safe
// alongside normal writes and has its own deadline; it never alters the data
// writer's deadline or waits behind the serialized request/ACK queue.
func (d *Default) ForegroundPingWriter() func(string, time.Time) error {
	socket := d.conn
	return func(token string, deadline time.Time) error {
		return socket.WriteControl(websocket.PingMessage, []byte(token), deadline)
	}
}
