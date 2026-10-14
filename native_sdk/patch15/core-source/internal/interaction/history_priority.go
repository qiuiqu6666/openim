package interaction

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/converter"
	"github.com/openimsdk/protocol/sdkws"
	"sort"
	"sync"
)

// Session-owned coordination: history reads and recovery share one lane per
// conversation. Only durably stored foreground rows are advertised as covered.
// No process-global account state or second message store is introduced.
type historyPriority struct {
	mu      sync.Mutex
	lanes   map[string]*historyLane
	covered map[string][]int64
	order   []string
}
type historyLane struct {
	token            chan struct{}
	refs, foreground int
}

func (l *LongConnMgr) LockMessageHistory(ctx context.Context, id string, foreground bool) (func(), error) {
	if l == nil {
		return func() {}, ctx.Err()
	}
	p := &l.historyPriority
	p.mu.Lock()
	if p.lanes == nil {
		p.lanes = make(map[string]*historyLane)
	}
	lane := p.lanes[id]
	if lane == nil {
		lane = &historyLane{token: make(chan struct{}, 1)}
		lane.token <- struct{}{}
		p.lanes[id] = lane
	}
	lane.refs++
	if foreground {
		lane.foreground++
	}
	p.mu.Unlock()
	drop := func() {
		p.mu.Lock()
		defer p.mu.Unlock()
		lane.refs--
		if foreground {
			lane.foreground--
		}
		if lane.refs == 0 {
			delete(p.lanes, id)
		}
	}
	select {
	case <-ctx.Done():
		drop()
		return nil, ctx.Err()
	case <-lane.token:
	}
	if err := ctx.Err(); err != nil {
		lane.token <- struct{}{}
		drop()
		return nil, err
	}
	var once sync.Once
	return func() { once.Do(func() { lane.token <- struct{}{}; drop() }) }, nil
}

func (l *LongConnMgr) RememberHistoryRows(id string, seqs []int64) {
	if l == nil || len(seqs) == 0 {
		return
	}
	p := &l.historyPriority
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.covered == nil {
		p.covered = make(map[string][]int64)
	}
	if _, ok := p.covered[id]; !ok {
		if len(p.order) >= 128 {
			delete(p.covered, p.order[0])
			p.order = p.order[1:]
		}
		p.order = append(p.order, id)
	}
	seen := make(map[int64]bool)
	for _, s := range append(append([]int64(nil), p.covered[id]...), seqs...) {
		if s > 0 {
			seen[s] = true
		}
	}
	rows := make([]int64, 0, len(seen))
	for s := range seen {
		rows = append(rows, s)
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i] < rows[j] })
	if len(rows) > recentMessageWindow {
		rows = rows[len(rows)-recentMessageWindow:]
	}
	p.covered[id] = rows
}

func (l *LongConnMgr) storedHistoryRanges(id string, r [2]int64) [][2]int64 {
	if l == nil {
		return nil
	}
	p := &l.historyPriority
	p.mu.Lock()
	defer p.mu.Unlock()
	var ranges [][2]int64
	for _, s := range p.covered[id] {
		if s < r[0] || s > r[1] {
			continue
		}
		if len(ranges) > 0 && ranges[len(ranges)-1][1]+1 == s {
			ranges[len(ranges)-1][1] = s
		} else {
			ranges = append(ranges, [2]int64{s, s})
		}
	}
	return ranges
}

type syncConversationPriority struct {
	pinned   bool
	activity int64
}

func (m *MsgSyncer) conversationPriorities(ctx context.Context) map[string]syncConversationPriority {
	result := make(map[string]syncConversationPriority)
	if m.db == nil {
		return result
	}
	rows, err := m.db.GetAllConversationListDB(ctx)
	if err != nil {
		return result
	} // Ordering is optional; synchronization still runs.
	for _, row := range rows {
		if row != nil {
			result[row.ConversationID] = syncConversationPriority{row.IsPinned, row.LatestMsgSendTime}
		}
	}
	return result
}

func (m *MsgSyncer) prioritizeConversations(ids []string, priorities map[string]syncConversationPriority) {
	active := make(map[string]bool)
	if m.longConnMgr != nil {
		p := &m.longConnMgr.historyPriority
		p.mu.Lock()
		for id, lane := range p.lanes {
			active[id] = lane.foreground > 0
		}
		p.mu.Unlock()
	}
	sort.SliceStable(ids, func(i, j int) bool {
		a, b := ids[i], ids[j]
		if active[a] != active[b] {
			return active[a]
		}
		x, y := priorities[a], priorities[b]
		if x.pinned != y.pinned {
			return x.pinned
		}
		return x.activity > y.activity
	})
}

// Called while holding the same lane as foreground storage. A sparse newest
// window remains sparse coverage; it must never advance across an older gap.
func (m *MsgSyncer) acceptStoredHistory(ctx context.Context, id string, r [2]int64, total int) error {
	if IsNotification(id) {
		return nil
	}
	ranges := m.longConnMgr.storedHistoryRanges(id, r)
	if len(ranges) == 0 {
		return nil
	}
	if m.db == nil {
		return nil
	}
	var seqs []int64
	for _, span := range ranges {
		for s := span[0]; s <= span[1]; s++ {
			if !m.messageAlreadyCovered(id, s) {
				seqs = append(seqs, s)
			}
		}
	}
	if len(seqs) == 0 {
		return nil
	}
	rows, err := m.db.GetMessagesBySeqs(ctx, id, seqs)
	if err != nil {
		return err
	}
	// Replay through the normal receipt path so adopting history preserves
	// conversation previews, unread reconciliation and durable acknowledgements.
	// Revalidate SQLite: clear-history may have removed a remembered row.
	sort.Slice(rows, func(i, j int) bool {
		if rows[i] == nil {
			return false
		}
		if rows[j] == nil {
			return true
		}
		return rows[i].Seq < rows[j].Seq
	})
	var groups [][]*sdkws.MsgData
	for _, row := range rows {
		if row == nil || row.Seq < r[0] || row.Seq > r[1] {
			continue
		}
		data := converter.MsgStructToMsgData(converter.LocalChatLogToMsgStruct(row), nil)
		if len(groups) > 0 && groups[len(groups)-1][len(groups[len(groups)-1])-1].Seq+1 == row.Seq {
			groups[len(groups)-1] = append(groups[len(groups)-1], data)
		} else {
			groups = append(groups, []*sdkws.MsgData{data})
		}
	}
	for _, group := range groups {
		resp := &sdkws.PullMessageBySeqsResp{Msgs: map[string]*sdkws.PullMsgs{id: {Msgs: group}}}
		if err = m.commitPulledMessages(ctx, resp, map[string][2]int64{id: {group[0].Seq, group[len(group)-1].Seq}}, total, true); err != nil {
			return err
		}
	}
	return nil
}

func (m *MsgSyncer) syncPrioritizedPage(ctx context.Context, id string, r [2]int64, total int) error {
	release, err := m.longConnMgr.LockMessageHistory(ctx, id, false)
	if err != nil {
		return err
	}
	defer release()
	if err = m.acceptStoredHistory(ctx, id, r, total); err != nil {
		return err
	}
	pages := [][2]int64{r}
	if !IsNotification(id) {
		pages = m.recentMissingRanges(id, r)
	}
	for _, page := range pages {
		batch := map[string][2]int64{id: page}
		resp, err := m.pullMsgBySeqRange(ctx, batch, page[1]-page[0]+1)
		if err != nil {
			return err
		}
		if err = m.commitPulledMessages(ctx, resp, batch, total); err != nil {
			return err
		}
	}
	return nil
}

func (m *MsgSyncer) lockPreviewHistory(ctx context.Context, batch map[string][2]int64) (func(), error) {
	ids := make([]string, 0, len(batch))
	for id := range batch {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	var releases []func()
	var once sync.Once
	release := func() {
		once.Do(func() {
			for i := len(releases) - 1; i >= 0; i-- {
				releases[i]()
			}
		})
	}
	for _, id := range ids {
		unlock, err := m.longConnMgr.LockMessageHistory(ctx, id, false)
		if err != nil {
			release()
			return nil, err
		}
		releases = append(releases, unlock)
	}
	return release, nil
}
