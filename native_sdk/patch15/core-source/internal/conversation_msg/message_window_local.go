package conversation_msg

import (
	"sort"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	sdk "github.com/openimsdk/openim-sdk-core/v3/pkg/sdk_params_callback"
)

// Local records decorate the covered server window without proving coverage or
// crossing a permission-empty boundary. Keep server sequence order intact.
func appendLocalWindowMessages(result *sdk.GetAdvancedHistoryMessageListCallback, read *model_struct.MessageWindowRead, remoteEmpty bool) {
	if remoteEmpty || read.Conversation.IsPrivateChat {
		return
	}
	var floor int64
	for _, row := range read.Rows {
		if row.Seq == result.Window.LowerBound {
			floor = row.SendTime
			break
		}
	}
	var local []*model_struct.LocalChatLog
	for _, row := range read.Rows {
		if row.Seq == 0 && row.Status == constant.MsgStatusSendSuccess &&
			row.ContentType != constant.Typing && row.SendTime >= floor {
			local = append(local, row)
		}
	}
	sort.SliceStable(local, func(i, j int) bool {
		if local[i].SendTime == local[j].SendTime {
			return local[i].ClientMsgID < local[j].ClientMsgID
		}
		return local[i].SendTime < local[j].SendTime
	})
	for _, row := range local {
		message := LocalChatLogToMsgStruct(row)
		if message.AttachedInfoElem.IsPrivateChat {
			continue
		}
		at := len(result.MessageList)
		for i, existing := range result.MessageList {
			if existing.SendTime > message.SendTime {
				at = i
				break
			}
		}
		result.MessageList = append(result.MessageList, nil)
		copy(result.MessageList[at+1:], result.MessageList[at:])
		result.MessageList[at] = message
	}
}
