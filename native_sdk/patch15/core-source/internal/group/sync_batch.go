package group

import (
	"context"
	"github.com/openimsdk/tools/log"
	"sync"
	"sync/atomic"
	"time"
)

// Bound database/profile work independently of the server's batch size.
// Cancellation stops dispatch and joins in-flight work before returning.
func runGroupSyncBatch(ctx context.Context, tasks []func() error) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if len(tasks) == 0 {
		return nil
	}
	const concurrency = 4
	var started, active, peak atomic.Int64
	var cancelledAt atomic.Int64
	stopNotice := context.AfterFunc(ctx, func() { cancelledAt.CompareAndSwap(0, time.Now().UnixNano()) })
	defer stopNotice()
	defer func() {
		join := time.Duration(0)
		if at := cancelledAt.Load(); at != 0 {
			join = time.Since(time.Unix(0, at))
		}
		log.ZDebug(ctx, "group_sync_batch_summary", "scheduled", len(tasks), "started", started.Load(), "peakActive", peak.Load(), "activeAtExit", active.Load(), "cancelled", ctx.Err() != nil, "cancelJoinElapsed", join)
	}()
	jobs := make(chan func() error)
	var wg sync.WaitGroup
	var firstErr error
	var once sync.Once
	for i := 0; i < concurrency; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for task := range jobs {
				if ctx.Err() != nil {
					return
				}
				started.Add(1)
				n := active.Add(1)
				for old := peak.Load(); n > old; old = peak.Load() {
					if peak.CompareAndSwap(old, n) {
						break
					}
				}
				err := task()
				active.Add(-1)
				if err != nil {
					once.Do(func() { firstErr = err })
				}
			}
		}()
	}
dispatch:
	for _, task := range tasks {
		if ctx.Err() != nil {
			break
		}
		select {
		case <-ctx.Done():
			break dispatch
		case jobs <- task:
		}
	}
	close(jobs)
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return err
	}
	return firstErr
}
