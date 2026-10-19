package interaction

import (
	"context"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/logpolicy"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/tools/errs"
	"net"
	"sync/atomic"
	"time"

	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/log"
)

// Diagnostics deliberately contain no message bodies, tokens or member profiles.
// One command owns this state; live pushes get a different context.
type syncDiagnosticKey struct{}
type syncDiagnostic struct {
	id                         uint64
	started                    time.Time
	pulls, mismatches, samples int
}

var syncDiagnosticSequence atomic.Uint64

func beginSyncDiagnostic(ctx context.Context, command string, initial bool) (context.Context, func()) {
	ctx = common.WithSyncMetrics(ctx)
	d := &syncDiagnostic{id: syncDiagnosticSequence.Add(1), started: time.Now()}
	ctx = context.WithValue(ctx, syncDiagnosticKey{}, d)
	if logpolicy.Enabled() || initial {
		log.ZInfo(ctx, "sync_diag attempt_start", "attempt", d.id, "command", command, "initial", initial)
	}
	return ctx, func() {
		common.FlushSyncMetrics(ctx, true)
		log.ZInfo(ctx, "sync_diag attempt_end", "attempt", d.id, "elapsed", time.Since(d.started).String(),
			"pulls", d.pulls, "coverageMismatches", d.mismatches, "samples", d.samples, "cancelled", ctx.Err() != nil)
	}
}

type syncPacketDiagnostic struct {
	Present bool  `json:"present"`
	Count   int   `json:"count"`
	IsEnd   bool  `json:"isEnd"`
	EndSeq  int64 `json:"endSeq"`
	MinSeq  int64 `json:"minSeq"`
	MaxSeq  int64 `json:"maxSeq"`
	Deleted int   `json:"deleted"`
	NilRows int   `json:"nilRows"`
}

func describeSyncPacket(packet *sdkws.PullMsgs) syncPacketDiagnostic {
	if packet == nil {
		return syncPacketDiagnostic{}
	}
	s := syncPacketDiagnostic{Present: true, Count: len(packet.Msgs), IsEnd: packet.IsEnd, EndSeq: packet.EndSeq}
	for _, row := range packet.Msgs {
		if row == nil {
			s.NilRows++
			continue
		}
		if s.MinSeq == 0 || row.Seq < s.MinSeq {
			s.MinSeq = row.Seq
		}
		if row.Seq > s.MaxSeq {
			s.MaxSeq = row.Seq
		}
		if row.Status >= 4 {
			s.Deleted++
		}
	}
	return s
}

func (m *MsgSyncer) diagnoseSyncPull(ctx context.Context, ranges map[string][2]int64, resp *sdkws.PullMessageBySeqsResp, elapsed time.Duration, pullErr error) {
	d, _ := ctx.Value(syncDiagnosticKey{}).(*syncDiagnostic)
	if d == nil {
		return
	}
	d.pulls++
	common.RecordSyncMetric(ctx, "range_fetch", 1, elapsed)
	if pullErr != nil {
		common.RecordSyncMetric(ctx, "range_request_failure_"+syncRangeFailureReason(nil, pullErr), 1, 0)
	}
	if resp != nil {
		var n int64
		for _, p := range resp.Msgs {
			if p != nil {
				n += int64(len(p.Msgs))
			}
		}
		common.RecordSyncMetric(ctx, "messages_fetched", n, 0)
	}
	missing, incomplete := 0, 0
	for id, requested := range ranges {
		var packet *sdkws.PullMsgs
		if resp != nil {
			if IsNotification(id) {
				packet = resp.NotificationMsgs[id]
			} else {
				packet = resp.Msgs[id]
			}
		}
		if packet == nil {
			missing++
		}
		if pullErr == nil && validatePulledConversationCoverage(map[string]*sdkws.PullMsgs{id: packet}, map[string][2]int64{id: requested}, IsNotification(id)) == nil {
			continue
		}
		incomplete++
		reason := syncRangeFailureReason(packet, pullErr)
		common.RecordSyncMetric(ctx, "range_incomplete_"+reason, 1, 0)
		d.mismatches++
		if d.samples >= 12 {
			continue
		}
		d.samples++
		fields := []any{"attempt", d.id, "pull", d.pulls, "conversationID", id, "requested", requested,
			"packet", describeSyncPacket(packet), "syncedSeq", m.syncedMaxSeqs[id], "checkpoint", m.checkpoints[id], "elapsed", elapsed.String()}
		if m.db != nil {
			conversation, err := m.db.GetConversation(ctx, id)
			fields = append(fields, "localReadFailed", err != nil)
			if conversation != nil {
				fields = append(fields, "localMinSeq", conversation.MinSeq, "localMaxSeq", conversation.MaxSeq)
			}
		}
		log.ZWarn(ctx, "sync_diag coverage_sample", pullErr, fields...)
	}
	if d.pulls <= 3 || d.pulls%100 == 0 || (incomplete > 0 && d.samples < 12) || elapsed > 2*time.Second {
		log.ZInfo(ctx, "sync_diag pull_summary", "attempt", d.id, "pull", d.pulls, "requestedConversations", len(ranges),
			"missingPackets", missing, "incompletePackets", incomplete, "elapsed", elapsed.String(), "transportFailed", pullErr != nil)
	}
}

// Server visibility proofs do not identify whether a boundary came from cleanup
// or permissions. Keep that cause unknown instead of inventing a legal hole.
func syncRangeFailureReason(packet *sdkws.PullMsgs, err error) string {
	if err != nil {
		if errors.Is(err, context.Canceled) {
			return "cancelled"
		}
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, sdkerrs.ErrCtxDeadline) {
			return "network_timeout"
		}
		if coded, ok := errs.Unwrap(err).(errs.CodeError); ok && coded.Code() == errs.NoPermissionError {
			return "permission_denied"
		}
		var network net.Error
		if errors.As(err, &network) {
			return "network_failure"
		}
		return "request_failure_unclassified"
	}
	if packet == nil {
		return "missing_packet"
	}
	if packet.IsEnd {
		return "boundary_claim_requires_confirmation"
	}
	if len(packet.Msgs) == 0 {
		return "empty_unconfirmed"
	}
	for _, row := range packet.Msgs {
		if row == nil {
			return "malformed_packet"
		}
	}
	return "unconfirmed_gap"
}
