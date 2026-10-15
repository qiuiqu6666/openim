package interaction

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
)

// A private namespace in the existing per-user version store. It is supported
// by both SQLite and IndexedDB, and older SDKs leave these rows untouched.
const messageCheckpointTable = "sdk_message_coverage_v1"

type messageCheckpoint struct {
	Completed int64 `json:"completed"`
	Target    int64 `json:"target"`
	// Covered records delivery coverage above Completed, not cache residency.
	// Its complement is historical data available on demand, never a background job.
	Covered   [][2]int64 `json:"covered,omitempty"`
	persisted bool
}

// MAX(seq) is an observation, never a proof of coverage. A legacy database
// replays its latest window once; existing rows are retained idempotently.
func (m *MsgSyncer) loadMessageCheckpoints(ctx context.Context, ids []string, snapshots ...map[string]*model_struct.LocalVersionSync) error {
	m.checkpoints = make(map[string]messageCheckpoint)
	m.checkpointIDs = make(map[string]bool)
	read := func(id string) (*model_struct.LocalVersionSync, error) {
		if len(snapshots) > 0 && snapshots[0] != nil {
			if row := snapshots[0][id]; row != nil {
				return row, nil
			}
			return nil, errs.ErrRecordNotFound
		}
		return m.db.GetVersionSync(ctx, messageCheckpointTable, id)
	}
	index, err := read("index")
	if err != nil && !errors.Is(err, errs.ErrRecordNotFound) {
		return err
	}
	if err == nil {
		for _, id := range index.UIDList {
			m.checkpointIDs[id] = true
		}
	}
	all := make(map[string]bool)
	for _, id := range ids {
		all[id] = true
	}
	for id := range m.checkpointIDs {
		all[id] = true
	}
	for id := range all {
		if IsNotification(id) {
			continue
		}
		state := messageCheckpoint{Target: m.syncedMaxSeqs[id]}
		row, err := read("conversation:" + id)
		if err != nil && !errors.Is(err, errs.ErrRecordNotFound) {
			return err
		}
		if err == nil {
			if err := json.Unmarshal([]byte(row.VersionID), &state); err != nil {
				return fmt.Errorf("invalid message checkpoint %q: %w", id, err)
			}
			if state.Completed < 0 || state.Target < state.Completed {
				return fmt.Errorf("invalid message checkpoint bounds %q", id)
			}
			for _, r := range state.Covered {
				if r[0] <= state.Completed || r[1] < r[0] || r[1] > state.Target {
					return fmt.Errorf("invalid sparse message coverage %q", id)
				}
			}
			state.persisted = true
			if m.syncedMaxSeqs[id] > state.Target {
				state.Target = m.syncedMaxSeqs[id]
				state.persisted = false
			}
		}
		m.checkpoints[id] = state
		m.syncedMaxSeqs[id] = state.Completed
	}
	return nil
}

func (m *MsgSyncer) saveMessageCheckpoint(ctx context.Context, id string, state messageCheckpoint) error {
	if IsNotification(id) {
		return nil
	}
	if m.checkpoints == nil {
		m.checkpoints = make(map[string]messageCheckpoint)
	}
	if m.db != nil {
		if err := m.registerMessageCheckpointIDs(ctx, []string{id}); err != nil {
			return err
		}
		payload, err := json.Marshal(state)
		if err != nil {
			return err
		}
		if err = m.db.SetVersionSync(ctx, &model_struct.LocalVersionSync{Table: messageCheckpointTable, EntityID: "conversation:" + id, Version: 1, VersionID: string(payload)}); err != nil {
			return err
		}
	}
	state.persisted = true
	m.checkpoints[id] = state
	return nil
}

func (m *MsgSyncer) rememberMessageTarget(ctx context.Context, id string, target int64) error {
	if IsNotification(id) {
		return nil
	}
	state, ok := m.checkpoints[id]
	if !ok {
		state.Completed = m.syncedMaxSeqs[id]
	}
	if ok && state.persisted && target <= state.Target {
		return nil
	}
	state.Target = max(state.Completed, max(state.Target, target))
	return m.saveMessageCheckpoint(ctx, id, state)
}

func (m *MsgSyncer) commitMessageCheckpoint(ctx context.Context, id string, end int64) error {
	if end <= m.syncedMaxSeqs[id] {
		return nil
	}
	if !IsNotification(id) {
		if err := m.commitMessageCoverage(ctx, id, [][2]int64{{m.syncedMaxSeqs[id] + 1, end}}); err != nil {
			return err
		}
		return nil
	}
	m.syncedMaxSeqs[id] = end
	return nil
}

// Register new conversations once per server snapshot instead of repeatedly
// rewriting a growing index when upgrading a large account.
func (m *MsgSyncer) registerMessageCheckpointIDs(ctx context.Context, ids []string) error {
	if m.db == nil {
		return nil
	}
	if m.checkpointIDs == nil {
		m.checkpointIDs = make(map[string]bool)
	}
	added := make(map[string]bool)
	for _, id := range ids {
		if !m.checkpointIDs[id] {
			added[id] = true
		}
	}
	if len(added) == 0 {
		return nil
	}
	all := make([]string, 0, len(m.checkpointIDs)+len(added))
	for id := range m.checkpointIDs {
		all = append(all, id)
	}
	for id := range added {
		all = append(all, id)
	}
	sort.Strings(all)
	if err := m.db.SetVersionSync(ctx, &model_struct.LocalVersionSync{Table: messageCheckpointTable, EntityID: "index", Version: 1, UIDList: all}); err != nil {
		return err
	}
	for id := range added {
		m.checkpointIDs[id] = true
	}
	return nil
}

// Only authenticated conversation metadata may waive an invisible prefix or
// limit a departed group's upper boundary. Empty pull responses cannot do so.
func (m *MsgSyncer) visibleMessageRange(ctx context.Context, id string, r [2]int64) ([2]int64, error) {
	r[0] = max(1, r[0])
	if m.db == nil || IsNotification(id) {
		return r, nil
	}
	c, err := m.db.GetConversation(ctx, id)
	if errors.Is(err, errs.ErrRecordNotFound) {
		return r, nil
	}
	if err != nil {
		return r, err
	}
	if c != nil {
		r[0] = max(r[0], c.MinSeq)
		if c.MaxSeq > 0 && r[1] > c.MaxSeq {
			// Legacy history reads also wrote MaxSeq. Revalidate a conflicting
			// bound instead of permanently suppressing a newer target.
			return m.refreshVisibleMessageRange(ctx, id, r)
		}
	}
	return r, nil
}
