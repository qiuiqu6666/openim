package interaction

// requestConnectionDone binds a response wait to the socket used for its write.
// The caller holds connWrite, so a redial cannot replace the socket in between.
func (c *LongConnMgr) requestConnectionDone() <-chan struct{} {
	c.w.Lock()
	defer c.w.Unlock()
	if c.connectionDone == nil {
		c.connectionDone = make(chan struct{})
		if c.connStatus != Connected {
			close(c.connectionDone)
		}
	}
	return c.connectionDone
}

// endConnectionRequestsLocked does not retry sent messages: the caller still
// receives the normal network error and owns any idempotent recovery policy.
func (c *LongConnMgr) endConnectionRequestsLocked() {
	if c.connectionDone == nil {
		return
	}
	select {
	case <-c.connectionDone:
	default:
		close(c.connectionDone)
	}
}
