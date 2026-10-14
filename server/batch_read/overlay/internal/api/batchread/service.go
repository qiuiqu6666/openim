// Package batchread batches existing read RPCs without bypassing receipts,
// authorization, visibility boundaries or multi-device notifications.
package batchread

import (
	"context"
	"sort"
	"strings"
	"sync"

	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/tools/errs"
)

const BatchSize = 100
const PrepareSize = 1000

type Target struct {
	ConversationID string `json:"conversationID"`
	HasReadSeq     int64  `json:"hasReadSeq"`
}
type Result struct {
	Target
	Success bool `json:"success"`
}
type Service struct {
	client msg.MsgClient
	slots  chan struct{}
}

func New(client msg.MsgClient) *Service {
	return &Service{client: client, slots: make(chan struct{}, 16)}
}

func matches(scope, id string) bool {
	single, group := strings.HasPrefix(id, "si_"), strings.HasPrefix(id, "sg_")
	return (scope == "single" && single) || (scope == "group" && group) || ((scope == "all" || scope == "selected") && (single || group))
}

// Prepare fixes the upper read watermark before any writes. An empty selected
// set must never accidentally mean all conversations to the underlying RPC.
func (s *Service) Prepare(ctx context.Context, user, scope string, ids []string) ([]Target, error) {
	if user == "" {
		return nil, errs.ErrNoPermission.WrapMsg("authentication required")
	}
	if scope != "single" && scope != "group" && scope != "all" && scope != "selected" {
		return nil, errs.ErrArgs.WrapMsg("invalid read scope")
	}
	if (scope != "selected" && len(ids) > 0) || len(ids) > PrepareSize {
		return nil, errs.ErrArgs.WrapMsg("invalid conversation selection")
	}
	targets := make([]Target, 0)
	if scope == "selected" && len(ids) == 0 {
		return targets, nil
	}
	for _, id := range ids {
		if !matches("selected", id) || len(id) > 512 {
			return nil, errs.ErrArgs.WrapMsg("invalid conversation ID")
		}
	}
	selected := make(map[string]bool, len(ids))
	for _, id := range ids {
		selected[id] = true
	}
	snapshot, err := s.client.GetConversationsHasReadAndMaxSeq(ctx, &msg.GetConversationsHasReadAndMaxSeqReq{UserID: user, ConversationIDs: ids})
	if err != nil {
		return nil, err
	}
	for id, seq := range snapshot.GetSeqs() {
		if matches(scope, id) && (scope != "selected" || selected[id]) && seq.GetMaxSeq() > seq.GetHasReadSeq() {
			targets = append(targets, Target{ConversationID: id, HasReadSeq: seq.GetMaxSeq()})
		}
	}
	sort.Slice(targets, func(i, j int) bool { return targets[i].ConversationID < targets[j].ConversationID })
	return targets, nil
}

func (s *Service) Apply(ctx context.Context, user string, targets []Target) ([]Result, error) {
	if user == "" {
		return nil, errs.ErrNoPermission.WrapMsg("authentication required")
	}
	if len(targets) == 0 || len(targets) > BatchSize {
		return nil, errs.ErrArgs.WrapMsg("invalid batch size")
	}
	ids := make([]string, 0, len(targets))
	seen := make(map[string]bool)
	for _, t := range targets {
		if !matches("selected", t.ConversationID) || len(t.ConversationID) > 512 || t.HasReadSeq <= 0 || seen[t.ConversationID] {
			return nil, errs.ErrArgs.WrapMsg("invalid or duplicate read target")
		}
		seen[t.ConversationID] = true
		ids = append(ids, t.ConversationID)
	}
	// Authorize the whole set and enforce each user's visible maximum, including
	// closed group membership ranges, before starting any mutation.
	snapshot, err := s.client.GetConversationsHasReadAndMaxSeq(ctx, &msg.GetConversationsHasReadAndMaxSeqReq{UserID: user, ConversationIDs: ids})
	if err != nil {
		return nil, err
	}
	results := make([]Result, len(targets))
	var wg sync.WaitGroup
	jobs := make(chan int)
	for w := 0; w < 8; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				t := targets[i]
				results[i] = Result{Target: t}
				seq, ok := snapshot.GetSeqs()[t.ConversationID]
				if !ok || t.HasReadSeq > seq.GetMaxSeq() {
					continue
				}
				select {
				case s.slots <- struct{}{}:
				case <-ctx.Done():
					continue
				}
				// Bound single-chat receipt arrays even for a very old unread conversation.
				cursor := seq.GetHasReadSeq()
				if cursor >= t.HasReadSeq {
					results[i].Success = true
				}
				for cursor < t.HasReadSeq && ctx.Err() == nil {
					next := t.HasReadSeq
					if strings.HasPrefix(t.ConversationID, "si_") && next-cursor > 2000 {
						next = cursor + 2000
					}
					var e error
					if strings.HasPrefix(t.ConversationID, "si_") {
						// The snapshot cursor can include minSeq-1 after history
						// deletion. Explicit sequences avoid the whole-conversation
						// RPC expanding that invisible gap from a lower stored cursor.
						seqs := make([]int64, next-cursor)
						for j := range seqs {
							seqs[j] = cursor + int64(j) + 1
						}
						_, e = s.client.MarkMsgsAsRead(ctx, &msg.MarkMsgsAsReadReq{UserID: user, ConversationID: t.ConversationID, Seqs: seqs})
					} else {
						_, e = s.client.MarkConversationAsRead(ctx, &msg.MarkConversationAsReadReq{UserID: user, ConversationID: t.ConversationID, HasReadSeq: next})
					}
					if e != nil {
						break
					}
					cursor = next
				}
				results[i].Success = cursor >= t.HasReadSeq
				<-s.slots
			}
		}()
	}
	for i := range targets {
		jobs <- i
	}
	close(jobs)
	wg.Wait()
	return results, nil
}
