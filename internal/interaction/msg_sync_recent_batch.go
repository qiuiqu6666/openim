package interaction

import (
	"context"
	"errors"
	"fmt"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/protocol/sdkws"
)

// Retain the existing 100-message response budget. Small gaps share a request;
// large gaps remain bounded, and notification state is always replayed alone.
func (m *MsgSyncer) nextRecoveryBatch(ids []string, pending map[string][][2]int64) map[string][2]int64 {
	batch := make(map[string][2]int64)
	remaining := int64(SplitPullMsgNum)
	for _, id := range ids {
		pages := pending[id]
		if len(pages) == 0 {
			continue
		}
		r := pages[len(pages)-1]
		r[0] = max(r[0], m.syncedMaxSeqs[id]+1)
		if r[0] > r[1] {
			pending[id] = pages[:len(pages)-1]
			if len(pending[id]) == 0 {
				delete(pending, id)
			}
			continue
		}
		if IsNotification(id) && len(batch) > 0 {
			continue
		}
		r[1] = min(r[1], r[0]+remaining-1)
		batch[id] = r
		remaining -= r[1] - r[0] + 1
		if IsNotification(id) || remaining == 0 || len(batch) == 8 {
			break
		}
	}
	return batch
}

func (m *MsgSyncer) pullMissingRecoveryBatch(ctx context.Context, batch map[string][2]int64, total int) map[string]error {
	failed := make(map[string]error)
	resp, err := m.pullMsgBySeqRange(ctx, batch, SplitPullMsgNum)
	if err != nil {
		// A connection timeout applies to the whole transport. Never multiply a
		// 30-second outage into one timeout per conversation in this batch.
		if len(batch) > 1 && ctx.Err() == nil && !errors.Is(err, sdkerrs.ErrCtxDeadline) {
			for id, r := range batch {
				for key, failure := range m.pullMissingRecoveryBatch(ctx, map[string][2]int64{id: r}, total) {
					failed[key] = failure
				}
			}
		} else {
			for id := range batch {
				failed[id] = err
			}
		}
		return failed
	}
	for id, r := range batch {
		if err := ctx.Err(); err != nil {
			failed[id] = err
			continue
		}
		var one *sdkws.PullMessageBySeqsResp
		if resp != nil {
			one = &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{}, NotificationMsgs: map[string]*sdkws.PullMsgs{}}
			if packet := resp.Msgs[id]; packet != nil {
				one.Msgs[id] = packet
			}
			if packet := resp.NotificationMsgs[id]; packet != nil {
				one.NotificationMsgs[id] = packet
			}
		}
		if err := m.commitPulledMessages(ctx, one, map[string][2]int64{id: r}, total); err != nil {
			failed[id] = err
		} else {
			messageSyncPageCommitted(ctx)
		}
	}
	return failed
}

func (m *MsgSyncer) recoverRecentMessagePages(ctx context.Context, ids []string, pending map[string][][2]int64, reinstall bool, totalPages int) []error {
	refreshed := make(map[string]bool)
	var failures []error
	priorities := m.conversationPriorities(ctx)
	ctx = context.WithValue(ctx, recoveryPriorityKey{}, priorities)
	for len(pending) > 0 {
		if err := yieldMessageSyncPage(ctx); err != nil {
			return append(failures, err)
		}
		m.prioritizeConversations(ids, priorities)
		batch := m.nextRecoveryBatch(ids, pending)
		if len(batch) == 0 {
			continue
		}
		total := 0
		if reinstall {
			total = totalPages
		}
		failed := m.pullRecoveryBatch(ctx, batch, total)
		if err := ctx.Err(); err != nil {
			return append(failures, err)
		}
		for id, r := range batch {
			if err := failed[id]; err != nil {
				var incomplete *incompleteMessageRange
				if errors.As(err, &incomplete) && !IsNotification(id) && !refreshed[id] {
					refreshed[id] = true
					pages := pending[id]
					remaining := [2]int64{r[0], pages[len(pages)-1][1]}
					visible, boundaryErr := m.refreshVisibleMessageRange(ctx, id, remaining)
					if boundaryErr == nil && visible != remaining {
						if visible[0] > r[0] {
							if commitErr := m.commitMessageCheckpoint(ctx, id, min(r[1], visible[0]-1)); commitErr != nil {
								return append(failures, commitErr)
							}
						}
						pending[id] = m.recentMissingRanges(id, visible)
						if len(pending[id]) == 0 {
							delete(pending, id)
						}
						continue
					}
					if boundaryErr != nil {
						err = errors.Join(err, boundaryErr)
					}
				}
				failures = append(failures, fmt.Errorf("message range %s [%d,%d]: %w", id, r[0], r[1], err))
				delete(pending, id)
				continue
			}
			pages := pending[id]
			page := pages[len(pages)-1]
			if r[1] == page[1] {
				pending[id] = pages[:len(pages)-1]
			} else {
				pages[len(pages)-1] = [2]int64{r[1] + 1, page[1]}
			}
			if len(pending[id]) == 0 {
				delete(pending, id)
			}
		}
	}
	return failures
}

// Share foreground history lanes and adopt only rows revalidated in SQLite.
// Locks are ordered by ID, and there is no concurrent coverage mutation.
func (m *MsgSyncer) pullRecoveryBatch(ctx context.Context, batch map[string][2]int64, total int) map[string]error {
	failed := make(map[string]error)
	release, err := m.lockPreviewHistory(ctx, batch)
	if err != nil {
		for id := range batch {
			failed[id] = err
		}
		return failed
	}
	defer release()
	missing := make(map[string][][2]int64)
	for id, r := range batch {
		if err := m.acceptStoredHistory(ctx, id, r, total); err != nil {
			failed[id] = err
			continue
		}
		if IsNotification(id) {
			missing[id] = [][2]int64{r}
		} else {
			missing[id] = m.recentMissingRanges(id, r)
		}
		if len(missing[id]) == 0 {
			delete(missing, id)
		}
	}
	for len(missing) > 0 {
		request := make(map[string][2]int64)
		for id, spans := range missing {
			request[id] = spans[0]
		}
		results := m.pullMissingRecoveryBatch(ctx, request, total)
		for id := range request {
			if err := results[id]; err != nil {
				failed[id] = err
				delete(missing, id)
			} else {
				missing[id] = missing[id][1:]
				if len(missing[id]) == 0 {
					delete(missing, id)
				}
			}
		}
	}
	return failed
}
