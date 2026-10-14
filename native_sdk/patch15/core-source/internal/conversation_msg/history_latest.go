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
	var rows []*model_struct.LocalChatLog
	result := &sdk.GetAdvancedHistoryMessageListCallback{}
	c.fetchAndMergeMissingMessages(ctx, id, seqs, false, count, 0, &rows, result)
	if result.ErrCode != 0 {
		return historyFetchError(result.ErrMsg)
	}
	return nil
}

type historyFetchError string

func (e historyFetchError) Error() string { return string(e) }
