package common

import (
	"context"
	"time"
)

type syncProgressKey struct{}

// ReportSyncProgress records completed work, never a timer-based heartbeat.
func ReportSyncProgress(ctx context.Context) {
	if ch, ok := ctx.Value(syncProgressKey{}).(chan struct{}); ok {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

// Metadata spans many individually bounded requests. Its watchdog measures
// inactivity instead of imposing the storage receipt's total 30-second budget.
func SendSyncCmdWithReceipt(ctx context.Context, value Cmd2Value, ch chan<- Cmd2Value) error {
	return sendSyncCmdWithReceipt(ctx, value, ch, 30*time.Second)
}

func sendSyncCmdWithReceipt(ctx context.Context, value Cmd2Value, ch chan<- Cmd2Value, idle time.Duration) error {
	workCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	progress := make(chan struct{}, 1)
	value.Ctx = context.WithValue(workCtx, syncProgressKey{}, progress)
	value.ExpiresAt = time.Time{}
	value.Receipt = make(chan error, 1)
	if err := sendCmd(ch, value, timeout); err != nil {
		return err
	}
	timer := time.NewTimer(idle)
	defer timer.Stop()
	for {
		select {
		case err := <-value.Receipt:
			return err
		case <-ctx.Done():
			return ctx.Err()
		case <-progress:
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			timer.Reset(idle)
		case <-timer.C:
			return context.DeadlineExceeded
		}
	}
}
