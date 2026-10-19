package common

import (
	"context"
	"testing"
	"time"
)

func TestSyncMetricsBoundSamplesAndSeparateTaskTime(t *testing.T) {
	ctx := WithSyncMetrics(context.Background())
	for i := 0; i < 10000; i++ {
		RecordSyncMetric(ctx, "db_batch_write", 1, time.Second)
	}
	m := ctx.Value(syncMetricsKey{}).(*SyncMetrics)
	if m.counts["db_batch_write"] != 10000 || m.totals["db_batch_write"] != 10000000 || len(m.durations["db_batch_write"]) != 4096 {
		t.Fatal("counts/totals/sampling invalid")
	}
	if time.Since(m.started) > time.Minute {
		t.Fatal("task sum was used as wall clock")
	}
}
