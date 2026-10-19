package common

import (
	"context"
	"fmt"
	"runtime"
	"runtime/debug"
	"strings"
	"time"

	"github.com/openimsdk/tools/log"
)

var packet string

func init() {
	build, ok := debug.ReadBuildInfo()
	if !ok {
		return
	}
	packet = build.Main.Path
	if packet != "" && !strings.HasSuffix(packet, "/") {
		packet += "/"
	}
}

type Cmd2Value struct {
	Cmd       string
	Value     any
	Caller    string
	Ctx       context.Context
	Receipt   chan error `json:"-"`
	ExpiresAt time.Time  `json:"-"`
}

func sendCmd(ch chan<- Cmd2Value, value Cmd2Value, timeout time.Duration) error {
	if value.Caller == "" {
		value.Caller = GetCaller(3)
	}
	if ch == nil {
		log.ZError(value.Ctx, "sendCmd chan is nil", ErrChanNil, "caller", value.Caller, "cmd", value.Cmd)
		return ErrChanNil
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	var cancelled <-chan struct{}
	if value.Ctx != nil {
		if err := value.Ctx.Err(); err != nil {
			return err
		}
		cancelled = value.Ctx.Done()
	}
	select {
	case <-cancelled:
		return value.Ctx.Err()
	case ch <- value:
		log.ZInfo(value.Ctx, "sendCmd chan success", "caller", value.Caller, "cmd", value.Cmd)
		return nil
	case <-timer.C:
		log.ZError(value.Ctx, "sendCmd chan timeout", ErrTimeout, "caller", value.Caller, "cmd", value.Cmd)
		return ErrTimeout
	}
}

// A successful enqueue is not confirmation that message storage succeeded.
func SendCmdWithReceipt(ctx context.Context, value Cmd2Value, ch chan<- Cmd2Value) error {
	// Bound queueing and acknowledgement together. Keep the original context
	// for callbacks that schedule follow-up work after this command completes.
	waitCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	value.Ctx = ctx
	value.ExpiresAt, _ = waitCtx.Deadline()
	value.Receipt = make(chan error, 1)
	if err := sendCmd(ch, value, timeout); err != nil {
		return err
	}
	select {
	case err := <-value.Receipt:
		return err
	case <-waitCtx.Done():
		return waitCtx.Err()
	}
}

func GetCaller(skip int) string {
	pc, _, line, ok := runtime.Caller(skip)
	if !ok {
		return "runtime.caller.failed"
	}
	name := runtime.FuncForPC(pc).Name()
	if packet != "" {
		name = strings.TrimPrefix(name, packet)
	}
	return fmt.Sprintf("%s:%d", name, line)
}

type goroutine interface {
	Work(cmd Cmd2Value)
	GetCh() chan Cmd2Value
}

func DoListener(ctx context.Context, li goroutine) {
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Sprintf("panic: %+v\n%s", r, debug.Stack())
			log.ZWarn(ctx, "DoListener panic", nil, "panic info", err)
		}
	}()
	if worker, ok := li.(interface{ InterruptibleCommand(Cmd2Value) bool }); ok {
		runInterruptibleListener(ctx, li, worker.InterruptibleCommand)
		return
	}

	for {
		select {
		case cmd, ok := <-li.GetCh():
			if !ok {
				return
			}
			log.ZInfo(cmd.Ctx, "recv cmd", "caller", cmd.Caller, "cmd", cmd.Cmd)
			runCommandSafely(li, cmd)
			log.ZInfo(cmd.Ctx, "done cmd", "caller", cmd.Caller, "cmd", cmd.Cmd)
		case <-ctx.Done():
			log.ZInfo(ctx, "conversation done sdk logout.....")
			return
		}
	}
}

// Recover per command so one malformed item cannot stop the receive worker.
func runCommandSafely(li goroutine, cmd Cmd2Value) {
	defer func() {
		if failure := recover(); failure != nil {
			log.ZWarn(cmd.Ctx, "conversation command panic", nil, "panic info",
				fmt.Sprintf("%v\n%s", failure, debug.Stack()))
		}
	}()
	li.Work(cmd)
}
