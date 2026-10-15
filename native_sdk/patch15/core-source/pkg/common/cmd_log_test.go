package common

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

type commandBodyProbe struct{ encoded atomic.Int32 }

func (v *commandBodyProbe) MarshalJSON() ([]byte, error) {
	v.encoded.Add(1)
	return []byte(`{"content":"message body"}`), nil
}

func TestCommandInfoLogDoesNotSerializePayload(t *testing.T) {
	probe := &commandBodyProbe{}
	ch := make(chan Cmd2Value, 1)
	if err := sendCmd(ch, Cmd2Value{Ctx: context.Background(), Cmd: "notification", Value: probe}, time.Second); err != nil {
		t.Fatal(err)
	}
	if (<-ch).Value != probe {
		t.Fatal("logging changed command payload")
	}
	if probe.encoded.Load() != 0 {
		t.Fatal("INFO log serialized the message page")
	}
}
