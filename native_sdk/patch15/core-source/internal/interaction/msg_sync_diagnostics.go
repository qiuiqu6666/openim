package interaction

import (
	"context"
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
	d := &syncDiagnostic{id: syncDiagnosticSequence.Add(1), started: time.Now()}
	ctx = context.WithValue(ctx, syncDiagnosticKey{}, d)
	log.ZInfo(ctx, "sync_diag attempt_start", "attempt", d.id, "command", command, "initial", initial)
	return ctx, func() {
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
