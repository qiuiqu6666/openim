package conversation_msg

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/tools/errs"
	"sort"
	"sync"
	"time"
)

// History callers and message delivery may enqueue concurrently. The mutex
// protects only queue bookkeeping; the serialized auxiliary worker owns all
// requests, coalescing group/UID retries without holding the mutex over I/O.
// No extra goroutine outlives login or mutates message cursors.
type profileKey struct{ group, uid string }

type profileQueue struct {
	mu        sync.Mutex
	pending   map[string]map[string]time.Time
	signalled bool
	recent    map[profileKey]time.Time
}

func (c *Conversation) queueMissingProfiles(ctx context.Context, groupID string, rows []*model_struct.LocalChatLog) {
	if c.sessionContext == nil || c.sessionContext.Err() != nil || ctx.Err() != nil {
		return
	}
	c.profileQueue.mu.Lock()
	defer c.profileQueue.mu.Unlock()
	for _, row := range rows {
		// Complete wire profiles are already usable; directory sync refreshes them.
		if row.SendID == "" || (row.SenderNickname != "" && row.SenderFaceURL != "") {
			continue
		}
		common.RecordSyncMetric(ctx, "profile_candidates", 1, 0)
		if checked := c.profileQueue.recent[profileKey{groupID, row.SendID}]; !checked.IsZero() && time.Since(checked) < time.Minute {
			common.RecordSyncMetric(ctx, "profile_deduplicated", 1, 0)
			continue
		}
		if c.profileQueue.pending == nil {
			c.profileQueue.pending = map[string]map[string]time.Time{}
		}
		if c.profileQueue.pending[groupID] == nil {
			c.profileQueue.pending[groupID] = map[string]time.Time{}
		}
		if _, ok := c.profileQueue.pending[groupID][row.SendID]; ok {
			common.RecordSyncMetric(ctx, "profile_deduplicated", 1, 0)
			continue
		}
		c.profileQueue.pending[groupID][row.SendID] = time.Now()
	}
	if len(c.profileQueue.pending) == 0 || c.profileQueue.signalled {
		return
	}
	select {
	case c.msgSyncerCh <- common.Cmd2Value{Ctx: c.sessionContext, Cmd: "syncAuxiliaryMetadata", Value: common.ProfileQueueWake{}}:
		c.profileQueue.signalled = true
	default: // Normal recovery/next incoming page also drains or signals this queue.
	}
}

func (c *Conversation) flushMissingProfiles(ctx context.Context) error {
	c.profileQueue.mu.Lock()
	c.profileQueue.signalled = false
	if len(c.profileQueue.pending) == 0 {
		c.profileQueue.mu.Unlock()
		return nil
	}
	var groups []string
	for id := range c.profileQueue.pending {
		groups = append(groups, id)
	}
	c.profileQueue.mu.Unlock()
	sort.Strings(groups)
	for _, id := range groups {
		for {
			if err := ctx.Err(); err != nil {
				return err
			}
			c.profileQueue.mu.Lock()
			var ids []string
			queuedAt := map[string]time.Time{}
			for uid, at := range c.profileQueue.pending[id] {
				queuedAt[uid] = at
				ids = append(ids, uid)
			}
			c.profileQueue.mu.Unlock()
			if len(ids) == 0 {
				break
			}
			sort.Strings(ids)
			if len(ids) > 100 {
				ids = ids[:100]
			}
			for _, uid := range ids {
				common.RecordSyncMetric(ctx, "profile_queue_wait", 1, time.Since(queuedAt[uid]))
			}
			started := time.Now()
			members, err := c.group.GetGroupMembersInfo(ctx, id, ids)
			common.RecordSyncMetric(ctx, "profile_lookup_batches", 1, time.Since(started))
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if err != nil {
				// Revoked permissions cannot be repaired by retrying optional profiles.
				if coded, ok := errs.Unwrap(err).(errs.CodeError); ok && coded.Code() == 1002 {
					c.profileQueue.mu.Lock()
					for uid := range c.profileQueue.pending[id] {
						c.profileQueue.checked(id, uid)
					}
					delete(c.profileQueue.pending, id)
					c.profileQueue.mu.Unlock()
					break
				}
				return err
			}
			for _, uid := range ids {
				if err := ctx.Err(); err != nil {
					return err
				}
				member := members[uid]
				if member != nil && member.Nickname != "" {
					args := common.UpdateMessageInfo{SessionType: constant.ReadGroupChatType, UserID: uid, GroupID: id, FaceURL: member.FaceURL, Nickname: member.Nickname}
					if err := c.db.UpdateMsgSenderFaceURLAndSenderNickname(ctx, c.getConversationIDBySessionType(id, constant.ReadGroupChatType), uid, member.FaceURL, member.Nickname); err != nil {
						return err
					}
					c.doUpdateConversation(common.Cmd2Value{Ctx: ctx, Value: common.UpdateConNode{Action: constant.UpdateLatestMessageFaceUrlAndNickName, Args: args}})
					c.group.PublishMessageProfile(ctx, member)
				}
				common.RecordSyncMetric(ctx, "profile_total_latency", 1, time.Since(queuedAt[uid]))
				c.profileQueue.mu.Lock()
				c.profileQueue.checked(id, uid)
				delete(c.profileQueue.pending[id], uid)
				if len(c.profileQueue.pending[id]) == 0 {
					delete(c.profileQueue.pending, id)
				}
				c.profileQueue.mu.Unlock()
			}
		}
	}
	return nil
}

// Successful empty profiles and permission denials are not network failures.
// A short bounded cooldown prevents users without avatars from triggering a
// new sweep for every message. It never covers message ranges or permissions.
// Caller holds mu. Eviction only permits an extra optional lookup.
func (q *profileQueue) checked(group, uid string) {
	if q.recent == nil {
		q.recent = map[profileKey]time.Time{}
	}
	if len(q.recent) >= 4096 {
		for key := range q.recent {
			delete(q.recent, key)
			break
		}
	}
	q.recent[profileKey{group, uid}] = time.Now()
}
