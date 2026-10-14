package interaction

import (
	"context"
	"errors"
	"fmt"
	"sort"
)

// Round-robin bounded pages keep a large or failing conversation from hiding
// another conversation's gap. There is one owner, inherited from the existing
// sync scheduler. A failed page is left pending for the next foreground tick.
func (m *MsgSyncer) syncCompleteMessageRanges(ctx context.Context, ranges map[string][2]int64, reinstall bool) error {
	leavePages := protectMessagePages(ctx)
	defer leavePages()
	m.recoveryReadSeqReady = false
	pending := make(map[string][2]int64, len(ranges))
	var ids []string
	var failures []error
	totalPages := 0
	refreshedBounds := make(map[string]bool)
	for id, r := range ranges {
		// Boundary revalidation can perform network I/O for many conversations.
		// Lend ownership between these checks as well as between message pages.
		if err := yieldMessageSyncPage(ctx); err != nil {
			return err
		}
		if err := m.rememberMessageTarget(ctx, id, r[1]); err != nil {
			return err
		}
		visible, err := m.visibleMessageRange(ctx, id, r)
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
		pending[id] = visible
		ids = append(ids, id)
		totalPages += int((visible[1]-visible[0])/SplitPullMsgNum + 1)
	}
	sort.Strings(ids)
	for len(pending) > 0 {
		for _, id := range ids {
			if err := yieldMessageSyncPage(ctx); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			r, ok := pending[id]
			if !ok {
				continue
			}
			r[0] = max(r[0], m.syncedMaxSeqs[id]+1)
			if r[0] > r[1] {
				delete(pending, id)
				continue
			}
			end := r[1]
			if r[1]-r[0] >= SplitPullMsgNum {
				end = r[0] + SplitPullMsgNum - 1
			}
			batch := map[string][2]int64{id: {r[0], end}}
			resp, err := m.pullMsgBySeqRange(ctx, batch, end-r[0]+1)
			if err == nil {
				total := 0
				if reinstall {
					total = totalPages
				}
				err = m.commitPulledMessages(ctx, resp, batch, total)
			}
			if err != nil {
				var incomplete *incompleteMessageRange
				if errors.As(err, &incomplete) && !IsNotification(id) && !refreshedBounds[id] {
					refreshedBounds[id] = true
					visible, boundaryErr := m.refreshVisibleMessageRange(ctx, id, r)
					if boundaryErr == nil && visible != r {
						if visible[0] > r[0] {
							if err := m.commitMessageCheckpoint(ctx, id, min(r[1], visible[0]-1)); err != nil {
								return err
							}
						}
						if visible[0] > visible[1] {
							delete(pending, id)
						} else {
							pending[id] = visible
						}
						continue
					}
					if boundaryErr != nil {
						err = errors.Join(err, boundaryErr)
					}
				}
				failures = append(failures, fmt.Errorf("message range %s [%d,%d]: %w", id, r[0], end, err))
				delete(pending, id)
				continue
			}
			messageSyncPageCommitted(ctx)
			if end == r[1] {
				delete(pending, id)
			} else {
				pending[id] = [2]int64{end + 1, r[1]}
			}
		}
	}
	return errors.Join(failures...)
}
