package conversation_msg

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
	"github.com/openimsdk/protocol/sdkws"
)

// An unanchored history query means latest, even when the local database has a
// full but stale page. It must not walk the entire gap from an old local row.
func (c *Conversation) ensureLatestHistory(ctx context.Context, id string, count int) error {
	if c.LongConnMgr == nil || !c.LongConnMgr.IsConnected() {
		return nil
	}
	var newest sdkws.GetMaxSeqResp
	if err := c.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{UserID: c.loginUserID}, constant.GetNewestSeq, &newest); err != nil {
		return err
	}
	end := newest.MaxSeqs[id]
	return c.ensureHistoryWindow(ctx, id, count, end)
}

func (c *Conversation) ensureHistoryWindow(ctx context.Context, id string, count int, end int64) error {
	release, err := c.LockMessageHistory(ctx, id, true)
	if err != nil {
		return err
	}
	defer release()
	if end <= 0 {
		return nil
	}
	count = min(max(count, 1), 100)
	visible, err := c.ResolveVisibleMessageRange(ctx, c.loginUserID, id, [2]int64{max(1, end-int64(count)+1), end})
	if err != nil {
		return err
	}
	if visible[0] > visible[1] {
		return nil
	}
	seqs := getLostSeqListWithLimitLength(visible[0], visible[1], nil, false)
	// A background page may have completed while this request waited for its
	// lane. Reuse durable rows, including deletion markers, before any download.
	existing, err := c.localLatestHistoryRows(ctx, id, seqs)
	if err != nil {
		return err
	}
	stored := make(map[int64]bool, len(existing))
	for _, row := range existing {
		if row != nil {
			stored[row.Seq] = true
		}
	}
	missing := make([]int64, 0, len(seqs))
	for _, seq := range seqs {
		if !stored[seq] {
			missing = append(missing, seq)
		}
	}
	var rows []*model_struct.LocalChatLog
	result := &sdk.GetAdvancedHistoryMessageListCallback{}
	if len(missing) > 0 {
		c.fetchAndMergeMissingMessages(ctx, id, missing, false, count, 0, &rows, result)
	}
	if result.ErrCode != 0 {
		return historyFetchError(result.ErrMsg)
	}
	// Re-read after storage; an explicit visibility boundary may have omitted
	// some requested sequences. Never claim those unpersisted rows as covered.
	persisted, err := c.localLatestHistoryRows(ctx, id, seqs)
	if err != nil {
		return err
	}
	covered := make([]int64, 0, len(persisted))
	for _, row := range persisted {
		if row != nil {
			covered = append(covered, row.Seq)
		}
	}
	c.RememberHistoryRows(id, covered)
	return nil
}

type historyFetchError string

func (e historyFetchError) Error() string { return string(e) }

// A new-device conversation may not have a message table yet.
func (c *Conversation) localLatestHistoryRows(ctx context.Context, id string, seqs []int64) ([]*model_struct.LocalChatLog, error) {
	localMax, err := c.db.CheckConversationNormalMsgSeq(ctx, id)
	if err != nil || localMax == 0 {
		return nil, err
	}
	return c.db.GetMessagesBySeqs(ctx, id, seqs)
}
