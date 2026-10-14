package interaction

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
)

const latestMessageBatchSize = 100

// Publish one latest message for every conversation before pulling any recent
// history. Batch conversations, rather than making one network trip per chat.
func (m *MsgSyncer) syncLatestMessagePreviews(ctx context.Context, ids []string, visible map[string][2]int64, total int) (map[string]error, error) {
	var singles, others []string
	for _, id := range ids {
		if IsNotification(id) || m.messageAlreadyCovered(id, visible[id][1]) {
			continue
		}
		if strings.HasPrefix(id, "si_") {
			singles = append(singles, id)
		} else {
			others = append(others, id)
		}
	}
	ordered := make([]string, 0, len(singles)+len(others))
	for i := 0; i < max(len(singles), len(others)); i++ {
		if i < len(singles) {
			ordered = append(ordered, singles[i])
		}
		if i < len(others) {
			ordered = append(ordered, others[i])
		}
	}
	failed := make(map[string]error)
	for begin := 0; begin < len(ordered); begin += latestMessageBatchSize {
		batch := make(map[string][2]int64)
		for _, id := range ordered[begin:min(begin+latestMessageBatchSize, len(ordered))] {
			end := visible[id][1]
			batch[id] = [2]int64{end, end}
		}
		if err := m.syncLatestMessageBatch(ctx, batch, visible, total, failed); err != nil {
			return failed, err
		}
	}
	return failed, nil
}

func (m *MsgSyncer) syncLatestMessageBatch(ctx context.Context, batch, visible map[string][2]int64, total int, failed map[string]error) error {
	if err := yieldMessageSyncPage(ctx); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	// A live push handled at the page boundary may already have stored the tail.
	for id, r := range batch {
		if m.messageAlreadyCovered(id, r[1]) || m.syncedMaxSeqs[id] >= r[1] {
			delete(batch, id)
		}
	}
	if len(batch) == 0 {
		return nil
	}
	resp, err := m.pullMsgBySeqRange(ctx, batch, 1)
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		// Isolate a bad conversation without discarding other previews in its batch.
		if len(batch) > 1 {
			for id, r := range batch {
				if err := m.syncLatestMessageBatch(ctx, map[string][2]int64{id: r}, visible, total, failed); err != nil {
					return err
				}
			}
		} else {
			for id, r := range batch {
				failed[id] = fmt.Errorf("latest message %s [%d]: %w", id, r[1], err)
			}
		}
		return nil
	}
	accepted := &sdkws.PullMessageBySeqsResp{Msgs: make(map[string]*sdkws.PullMsgs)}
	var deleted []string
	for id, r := range batch {
		if resp == nil {
			err = fmt.Errorf("empty latest-message response")
		} else {
			err = validatePulledConversationCoverage(resp.Msgs, map[string][2]int64{id: r}, false)
		}
		if err != nil {
			failed[id] = fmt.Errorf("latest message %s: %w", id, err)
			delete(batch, id)
			continue
		}
		accepted.Msgs[id] = resp.Msgs[id]
		if resp.Msgs[id].Msgs[0].Status == constant.MsgStatusHasDeleted {
			deleted = append(deleted, id)
		}
	}
	// The maximum sequence can be a deletion placeholder. Recover the last
	// visible message too, including one older than the automatic 100-row window.
	if len(deleted) > 0 {
		last, fetchErr := m.fetchLatestValidMessages(ctx, deleted)
		fallback := make(map[string]*sdkws.PullMsgs)
		for _, id := range deleted {
			if fetchErr != nil || last == nil {
				failed[id] = fmt.Errorf("latest valid message %s: %v", id, fetchErr)
				delete(batch, id)
				delete(accepted.Msgs, id)
				continue
			}
			row := last.Msgs[id]
			if row == nil {
				continue // No remaining visible message.
			}
			minimum := int64(1)
			if m.db != nil {
				conversation, readErr := m.db.GetConversation(ctx, id)
				if readErr != nil && !errors.Is(readErr, errs.ErrRecordNotFound) {
					failed[id] = fmt.Errorf("latest valid message %s boundary: %w", id, readErr)
					delete(batch, id)
					delete(accepted.Msgs, id)
					continue
				}
				if conversation != nil {
					minimum = max(minimum, conversation.MinSeq)
				}
			}
			if row.Seq < minimum || row.Seq > visible[id][1] || row.Status >= constant.MsgStatusHasDeleted {
				failed[id] = fmt.Errorf("invalid latest valid message for %s", id)
				delete(batch, id)
				delete(accepted.Msgs, id)
				continue
			}
			fallback[id] = &sdkws.PullMsgs{Msgs: []*sdkws.MsgData{row}}
		}
		if len(fallback) > 0 {
			if total > 0 {
				err = m.triggerReinstallConversation(ctx, fallback, total, true)
			} else {
				err = common.SendCmdWithReceipt(ctx, common.Cmd2Value{Cmd: constant.CmdNewMsgCome,
					Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: fallback, Recovery: true, ReconcileReadSeq: !m.recoveryReadSeqReady}}, m.conversationCh)
				if err == nil {
					m.recoveryReadSeqReady = true
				}
			}
			for id, packet := range fallback {
				commitErr := err
				if commitErr == nil {
					seq := packet.Msgs[0].Seq
					commitErr = m.commitMessageCoverage(ctx, id, [][2]int64{{seq, seq}})
				}
				if commitErr != nil {
					failed[id] = fmt.Errorf("latest valid message %s: %w", id, commitErr)
					delete(batch, id)
					delete(accepted.Msgs, id)
				}
			}
		}
	}
	if len(batch) > 0 {
		if err := m.commitPulledMessages(ctx, accepted, batch, total, true); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if len(batch) > 1 {
				for id, r := range batch {
					if err := m.syncLatestMessageBatch(ctx, map[string][2]int64{id: r}, visible, total, failed); err != nil {
						return err
					}
				}
			} else {
				for id := range batch {
					failed[id] = fmt.Errorf("latest message %s commit: %w", id, err)
				}
			}
		} else {
			messageSyncPageCommitted(ctx)
		}
	}
	return ctx.Err()
}
