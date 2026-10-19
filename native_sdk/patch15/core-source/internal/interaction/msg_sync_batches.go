package interaction

import (
	"context"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"sort"
)

// Round-robin bounded pages keep a large or failing conversation from hiding
// another conversation's gap. There is one owner, inherited from the existing
// sync scheduler. A failed page is left pending for the next foreground tick.
func (m *MsgSyncer) syncCompleteMessageRanges(ctx context.Context, ranges map[string][2]int64, reinstall bool) error {
	leavePages := protectMessagePages(ctx)
	defer leavePages()
	m.recoveryReadSeqReady = common.RecoveryMetadataPrepared(ctx)
	pending := make(map[string][][2]int64, len(ranges))
	var ids []string
	var failures []error
	totalPages := 0
	visibleRanges := make(map[string][2]int64, len(ranges))
	validatedRanges, boundaryFailures, recoveryOrder := m.visibleMessageRanges(ctx, ranges)
	for id, r := range ranges {
		// Boundary revalidation can perform network I/O for many conversations.
		// Lend ownership between these checks as well as between message pages.
		if err := yieldMessageSyncPage(ctx); err != nil {
			return err
		}
		if err := m.rememberMessageTarget(ctx, id, r[1]); err != nil {
			return err
		}
		visible, err := validatedRanges[id], boundaryFailures[id]
		if err != nil {
			failures = append(failures, err)
			continue
		}
		if visible[0] > r[0] && visible[0]-1 > m.syncedMaxSeqs[id] {
			if err := m.commitMessageCheckpoint(ctx, id, min(r[1], visible[0]-1)); err != nil {
				return err
			}
		}
		if visible[0] > visible[1] {
			continue
		}
		if IsNotification(id) {
			pending[id] = [][2]int64{visible}
		} else {
			pending[id] = m.recentMissingRanges(id, visible)
			if len(pending[id]) == 0 {
				delete(pending, id)
				continue
			}
		}
		ids = append(ids, id)
		visibleRanges[id] = visible
		for _, page := range pending[id] {
			totalPages += int((page[1]-page[0])/SplitPullMsgNum + 1)
		}
		if !IsNotification(id) && !m.messageAlreadyCovered(id, visible[1]) {
			last := pending[id][len(pending[id])-1]
			if last[0] < last[1] {
				totalPages++ // The preview and remaining tail have separate receipts.
			}
		}
	}
	priority := make(map[string]int, len(recoveryOrder))
	for n, id := range recoveryOrder {
		priority[id] = n
	}
	sort.SliceStable(ids, func(i, j int) bool { return priority[ids[i]] < priority[ids[j]] })
	previewTotal := 0
	if reinstall {
		previewTotal = totalPages
	}
	failedPreviews, err := m.syncLatestMessagePreviews(ctx, ids, visibleRanges, previewTotal)
	if err != nil {
		return err
	}
	for id, failure := range failedPreviews {
		failures = append(failures, failure)
		delete(pending, id) // Keep its durable target for the next attempt.
	}
	// Preview receipts cover only their own sequences. Recompute the recent
	// gaps so backfill neither downloads that row again nor skips older gaps.
	for id := range pending {
		if !IsNotification(id) {
			pending[id] = m.recentMissingRanges(id, visibleRanges[id])
			if len(pending[id]) == 0 {
				delete(pending, id)
			}
		}
	}
	failures = append(failures, m.recoverRecentMessagePages(ctx, ids, pending, reinstall, totalPages)...)
	if len(failures) > 0 {
		return errors.Join(failures...)
	}
	// Out-of-order live rows may close the whole latest window before the
	// recovery job runs. Reconcile unread even when no message page is missing.
	if m.pendingReadReconcile && !reinstall {
		if !m.recoveryReadSeqReady {
			if err := common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: constant.CmdNewMsgCome, Value: sdk_struct.CmdNewMsgComeToConversation{ReconcileReadSeq: true, Recovery: true}}, m.conversationCh); err != nil {
				return err
			}
		}
		m.pendingReadReconcile = false
	}
	return nil
}
