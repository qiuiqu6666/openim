package interaction

import (
	"context"
	"sort"
)

// Automatic recovery is bounded independently of a group's lifetime history.
const recentMessageWindow = 100

func (m *MsgSyncer) messageAlreadyCovered(id string, seq int64) bool {
	for _, r := range m.checkpoints[id].Covered {
		if seq >= r[0] && seq <= r[1] {
			return true
		}
	}
	return false
}

// commitMessageCoverage never mistakes the newest observed message for a
// complete prefix. Old ranges may be forgotten conservatively: their content
// remains queryable on demand and is never scheduled for background download.
func (m *MsgSyncer) commitMessageCoverage(ctx context.Context, id string, ranges [][2]int64) error {
	state := m.checkpoints[id]
	state.Completed = max(state.Completed, m.syncedMaxSeqs[id])
	all := append(append([][2]int64(nil), state.Covered...), ranges...)
	sort.Slice(all, func(i, j int) bool { return all[i][0] < all[j][0] })
	merged := make([][2]int64, 0, len(all))
	for _, r := range all {
		state.Target = max(state.Target, r[1])
		if r[1] <= state.Completed {
			continue
		}
		if r[0] <= state.Completed+1 {
			state.Completed = r[1]
			continue
		}
		if len(merged) > 0 && r[0] <= merged[len(merged)-1][1]+1 {
			merged[len(merged)-1][1] = max(merged[len(merged)-1][1], r[1])
		} else {
			merged = append(merged, r)
		}
	}
	// A bounded journal, rather than one item per missing sequence.
	if len(merged) > recentMessageWindow {
		merged = merged[len(merged)-recentMessageWindow:]
	}
	state.Covered = merged
	if err := m.saveMessageCheckpoint(ctx, id, state); err != nil {
		return err
	}
	m.syncedMaxSeqs[id] = state.Completed
	return nil
}

func (m *MsgSyncer) recentMissingRanges(id string, r [2]int64) [][2]int64 {
	r[0] = max(max(1, r[0]), r[1]-recentMessageWindow+1)
	state := m.checkpoints[id]
	r[0] = max(r[0], m.syncedMaxSeqs[id]+1)
	var missing [][2]int64
	for _, covered := range state.Covered {
		if covered[1] < r[0] {
			continue
		}
		if covered[0] > r[1] {
			break
		}
		if covered[0] > r[0] {
			missing = append(missing, [2]int64{r[0], covered[0] - 1})
		}
		r[0] = max(r[0], covered[1]+1)
	}
	if r[0] <= r[1] {
		missing = append(missing, r)
	}
	return missing
}
