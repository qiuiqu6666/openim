// Copyright 漏 2023 OpenIM SDK. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package conversation_msg

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/logpolicy"
	"reflect"
	"runtime"
	"sync"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"

	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/log"
)

const (
	syncWait = iota
	asyncNoWait
	asyncWait
)

// InitSyncProgress is initialize Sync when reinstall.
const InitSyncProgress = 10

func (c *Conversation) Work(c2v common.Cmd2Value) {
	var workErr error
	defer func() {
		if failure := recover(); failure != nil {
			if c2v.Receipt != nil {
				c2v.Receipt <- fmt.Errorf("conversation work panic: %v", failure)
			}
			panic(failure)
		}
		if c2v.Receipt != nil {
			c2v.Receipt <- workErr
		}
	}()
	if c2v.Ctx != nil && c2v.Ctx.Err() != nil {
		workErr = c2v.Ctx.Err()
		return
	}
	if !c2v.ExpiresAt.IsZero() && !time.Now().Before(c2v.ExpiresAt) {
		workErr = context.DeadlineExceeded
		return
	}
	log.ZDebug(c2v.Ctx, "NotificationCmd start", "caller", c2v.Caller, "cmd", c2v.Cmd, "value", c2v.Value)
	defer log.ZDebug(c2v.Ctx, "NotificationCmd end", "caller", c2v.Caller, "cmd", c2v.Cmd, "value", c2v.Value)
	switch c2v.Cmd {
	case constant.CmdNewMsgCome:
		workErr = c.doMsgNew(c2v)
	case constant.CmdUpdateConversation:
		c.doUpdateConversation(c2v)
	case constant.CmdUpdateMessage:
		c.doUpdateMessage(c2v)
	case constant.CmdNotification:
		workErr = c.doNotificationManager(c2v)
	case common.CmdSyncMissingProfiles:
		workErr = c.flushMissingProfiles(c2v.Ctx)
	case constant.CmdSyncData:
		workErr = c.syncData(c2v)
	case constant.CmdSyncFlag:
		workErr = c.syncFlag(c2v)
	case constant.CmdMsgSyncInReinstall:
		workErr = c.doMsgSyncByReinstalled(c2v)
	}
}

func (c *Conversation) syncFlag(c2v common.Cmd2Value) error {
	ctx, cancel := syncCommandContext(c2v)
	defer cancel()
	syncFlag := c2v.Value.(sdk_struct.CmdNewMsgComeToConversation).SyncFlag
	switch syncFlag {
	case constant.AppDataSyncStart:
		log.ZDebug(ctx, "AppDataSyncStart")
		c.startTime = time.Now()
		c.progress = 0
		c.msgOffset = 0
		c.ConversationListener().OnSyncServerStart(true)
		c.ConversationListener().OnSyncServerProgress(1)
		// Visibility/settings and read watermarks are the required bootstrap.
		// Friends and group-member profiles are refreshed by the serialized
		// auxiliary job after messages, without delaying this first window.
		c.addInitProgress(InitSyncProgress * 4 / 10)              // add 40% of InitSyncProgress as progress
		c.ConversationListener().OnSyncServerProgress(c.progress) // notify server current Progress

		syncWaitFunctions := []func(c context.Context) error{
			c.IncrSyncConversations,
			c.SyncAllConversationHashReadSeqs,
		}
		if err := runRequiredSyncFunctions(ctx, syncWaitFunctions, false); err != nil {
			return err
		}
		log.ZWarn(ctx, "core data sync over", nil, "cost time", time.Since(c.startTime).String())
		c.addInitProgress(InitSyncProgress * 6 / 10)              // add 60% of InitSyncProgress as progress
		c.ConversationListener().OnSyncServerProgress(c.progress) // notify server current Progress

	case constant.AppDataSyncFinish:
		if err := c.reconcileGroupConversationProfiles(ctx); err != nil {
			return err
		}
		log.ZDebug(ctx, "AppDataSyncFinish", "time", time.Since(c.startTime).String())
		c.progress = 100
		c.ConversationListener().OnSyncServerProgress(c.progress)
		c.ConversationListener().OnSyncServerFinish(true)
	case constant.MsgSyncBegin:
		log.ZDebug(ctx, "MsgSyncBegin")
		c.ConversationListener().OnSyncServerStart(false)
		// Only visibility/settings and read watermarks precede message recovery.
		// Profile, friend and member refreshes run after message delivery, so a
		// failing unrelated endpoint cannot suppress the newest offline message.
		return runRequiredSyncFunctions(ctx, []func(context.Context) error{
			c.IncrSyncConversationsWithLock,
			c.SyncAllConversationHashReadSeqs,
		}, false)
	case constant.MsgSyncFailed:
		c.ConversationListener().OnSyncServerFailed(false)
	case constant.MsgSyncEnd:
		log.ZDebug(ctx, "MsgSyncEnd", "time", time.Since(c.startTime).String())
		c.ConversationListener().OnSyncServerFinish(false)
	}
	return nil
}

func (c *Conversation) doNotificationManager(c2v common.Cmd2Value) error {
	ctx, cancel := syncCommandContext(c2v)
	defer cancel()
	allMsg := c2v.Value.(sdk_struct.CmdNewMsgComeToConversation).Msgs

	for conversationID, msgs := range allMsg {
		started := time.Now()
		if len(msgs.Msgs) > 0 {
			log.ZInfo(ctx, "notification page processing started", "conversationID", conversationID, "count", len(msgs.Msgs), "firstSeq", msgs.Msgs[0].Seq, "lastSeq", msgs.Msgs[len(msgs.Msgs)-1].Seq)
		}
		log.ZDebug(ctx, "notification handling", "conversationID", conversationID, "msgs", msgs)

		// First, process all the notifications
		for _, msg := range msgs.Msgs {
			if err := ctx.Err(); err != nil {
				return err
			}
			// Deleted sequence placeholders have no notification payload. They
			// still count towards the page checkpoint, but must not be dispatched.
			if msg.Status >= constant.MsgStatusHasDeleted && msg.Seq > 0 {
				continue
			}
			if msg.ContentType > constant.FriendNotificationBegin && msg.ContentType < constant.FriendNotificationEnd {
				if err := c.relation.DoNotification(ctx, msg); err != nil {
					return err
				}
			} else if msg.ContentType > constant.UserNotificationBegin && msg.ContentType < constant.UserNotificationEnd {
				c.user.DoNotification(ctx, msg)
			} else if msg.ContentType > constant.GroupNotificationBegin && msg.ContentType < constant.GroupNotificationEnd {
				if err := c.group.DoNotification(ctx, msg); err != nil {
					return err
				}
			} else {
				if err := c.doNotification(ctx, msg); err != nil {
					log.ZWarn(ctx, "notification page processing failed", err, "conversationID", conversationID, "seq", msg.Seq, "contentType", msg.ContentType, "clientMsgID", msg.ClientMsgID, "contextError", ctx.Err(), "duration", time.Since(started).String())
					return err
				}
			}
		}

		// After all notifications are processed, update the sequence number
		if err := ctx.Err(); err != nil {
			return err
		}
		if len(msgs.Msgs) != 0 {
			lastMsg := msgs.Msgs[len(msgs.Msgs)-1]
			log.ZDebug(ctx, "SetNotificationSeq", "conversationID", conversationID, "seq", lastMsg.Seq)
			if lastMsg.Seq != 0 {
				if err := c.db.SetNotificationSeq(ctx, conversationID, lastMsg.Seq); err != nil {
					// Log an error if setting the sequence number fails
					log.ZError(ctx, "SetNotificationSeq err", err, "conversationID", conversationID, "seq", lastMsg.Seq, "contextError", ctx.Err())
					return err
				}
				log.ZInfo(ctx, "notification page persisted", "conversationID", conversationID, "seq", lastMsg.Seq, "count", len(msgs.Msgs), "duration", time.Since(started).String())
			}
		}
	}
	return nil
}

func (c *Conversation) DoNotification(ctx context.Context, msg *sdkws.MsgData) {
	if err := c.doNotification(ctx, msg); err != nil {
		log.ZWarn(ctx, "DoConversationNotification failed", err)
	}
}

func (c *Conversation) doNotification(ctx context.Context, msg *sdkws.MsgData) error {
	switch msg.ContentType {
	case constant.ConversationChangeNotification:
		return c.DoConversationChangedNotification(ctx, msg)
	case constant.ConversationPrivateChatNotification: // 1701
		return c.DoConversationIsPrivateChangedNotification(ctx, msg)
	case constant.BusinessNotification:
		return c.doBusinessNotification(ctx, msg)
	case constant.RevokeNotification: // 2101
		return c.doRevokeMsg(ctx, msg)
	case constant.ClearConversationNotification: // 1703
		return c.doClearConversations(ctx, msg)
	case constant.DeleteMsgsNotification:
		return c.doDeleteMsgs(ctx, msg)
	case constant.HasReadReceipt: // 2200
		return c.doReadDrawing(ctx, msg)
	}
	return errs.New("unknown tips type", "contentType", msg.ContentType).Wrap()
}

func (c *Conversation) getConversationLatestMsgClientID(latestMsg string) string {
	msg := &sdk_struct.MsgStruct{}
	if err := json.Unmarshal([]byte(latestMsg), msg); err != nil {
		log.ZError(context.Background(), "getConversationLatestMsgClientID", err, "latestMsg", latestMsg)
	}
	return msg.ClientMsgID
}

func (c *Conversation) doUpdateConversation(c2v common.Cmd2Value) {
	if c2v.Caller == "" {
		c2v.Caller = common.GetCaller(2)
	}
	ctx := c2v.Ctx
	node := c2v.Value.(common.UpdateConNode)
	if logpolicy.Enabled() {
		log.ZInfo(ctx, "doUpdateConversation", "action", node.Action, "conversationID", node.ConID, "cmd", c2v.Cmd, "caller", c2v.Caller)
	}
	switch node.Action {
	case constant.AddConOrUpLatMsg:
		var list []*model_struct.LocalConversation
		lc := node.Args.(model_struct.LocalConversation)
		oc, err := c.db.GetConversation(ctx, lc.ConversationID)
		if err == nil {
			if lc.LatestMsgSendTime >= oc.LatestMsgSendTime || c.getConversationLatestMsgClientID(lc.LatestMsg) == c.getConversationLatestMsgClientID(oc.LatestMsg) { // The session update of asynchronous messages is subject to the latest sending time
				err := c.db.UpdateColumnsConversation(ctx, node.ConID, map[string]interface{}{"latest_msg_send_time": lc.LatestMsgSendTime, "latest_msg": lc.LatestMsg})
				if err != nil {
					log.ZError(ctx, "updateConversationLatestMsgModel", err, "conversationID", node.ConID)
				} else {
					oc.LatestMsgSendTime = lc.LatestMsgSendTime
					oc.LatestMsg = lc.LatestMsg
					list = append(list, oc)
					data := utils.StructToJsonString(list)
					log.ZDebug(ctx, "OnConversationChanged", "data", data)
					c.ConversationListener().OnConversationChanged(data)
				}
			}
		} else {
			log.ZDebug(ctx, "new conversation", "lc", lc)
			err4 := c.db.InsertConversation(ctx, &lc)
			if err4 != nil {
				log.ZWarn(ctx, "insert new conversation err", err4)
			} else {
				list = append(list, &lc)
				c.ConversationListener().OnNewConversation(utils.StructToJsonString(list))
			}
		}

	case constant.TotalUnreadMessageChanged:
		totalUnreadCount, err := c.db.GetTotalUnreadMsgCountDB(ctx)
		if err != nil {
			log.ZWarn(ctx, "GetTotalUnreadMsgCountDB err", err)
		} else {
			c.ConversationListener().OnTotalUnreadMessageCountChanged(totalUnreadCount)
		}
	case constant.UpdateConFaceUrlAndNickName:
		var lc model_struct.LocalConversation
		st := node.Args.(common.SourceIDAndSessionType)
		if logpolicy.Enabled() {
			log.ZInfo(ctx, "UpdateConFaceUrlAndNickName", "sessionType", st.SessionType)
		}
		switch st.SessionType {
		case constant.SingleChatType:
			lc.UserID = st.SourceID
			lc.ConversationID = c.getConversationIDBySessionType(st.SourceID, constant.SingleChatType)
			lc.ConversationType = constant.SingleChatType
		case constant.ReadGroupChatType:
			conversationID, conversationType, err := c.getConversationTypeByGroupID(ctx, st.SourceID)
			if err != nil {
				return
			}
			lc.GroupID = st.SourceID
			lc.ConversationID = conversationID
			lc.ConversationType = conversationType
			// Catchup reconciliation may already have committed this profile.
			// Its queued group notifications must not rewrite and republish it.
			if current, err := c.db.GetConversation(ctx, conversationID); err == nil &&
				current.ShowName == st.Nickname && current.FaceURL == st.FaceURL {
				return
			}
		case constant.NotificationChatType:
			lc.UserID = st.SourceID
			lc.ConversationID = c.getConversationIDBySessionType(st.SourceID, constant.NotificationChatType)
			lc.ConversationType = constant.NotificationChatType
		default:
			log.ZError(ctx, "not support sessionType", nil, "sessionType", st.SessionType)
			return
		}
		lc.ShowName = st.Nickname
		lc.FaceURL = st.FaceURL
		var err error
		if st.SessionType == constant.ReadGroupChatType {
			// Map updates preserve explicit avatar removal (empty string).
			err = c.db.UpdateColumnsConversation(ctx, lc.ConversationID, map[string]interface{}{"show_name": st.Nickname, "face_url": st.FaceURL})
		} else {
			err = c.db.UpdateConversation(ctx, &lc)
		}
		if err != nil {
			// log.Error("internal", "setConversationFaceUrlAndNickName database err:", err.Error())
			return
		}
		c.doUpdateConversation(common.Cmd2Value{Value: common.UpdateConNode{ConID: lc.ConversationID, Action: constant.ConChange, Args: []string{lc.ConversationID}}})

	case constant.UpdateLatestMessageReadState:
		conversationID := node.ConID
		var latestMsg sdk_struct.MsgStruct
		l, err := c.db.GetConversation(ctx, conversationID)
		if err != nil {
			log.ZError(ctx, "getConversationLatestMsgModel err", err, "conversationID", conversationID)
		} else {
			err := json.Unmarshal([]byte(l.LatestMsg), &latestMsg)
			if err != nil {
				log.ZError(ctx, "latestMsg,Unmarshal err", err)
			} else {
				latestMsg.IsRead = true
				newLatestMessage := utils.StructToJsonString(latestMsg)
				err = c.db.UpdateColumnsConversation(ctx, node.ConID, map[string]interface{}{"latest_msg_send_time": latestMsg.SendTime, "latest_msg": newLatestMessage})
				if err != nil {
					log.ZError(ctx, "updateConversationLatestMsgModel err", err)
				}
			}
		}
	case constant.UpdateLatestMessageFaceUrlAndNickName:
		args := node.Args.(common.UpdateMessageInfo)
		switch args.SessionType {
		case constant.ReadGroupChatType:
			conversationID := c.getConversationIDBySessionType(args.GroupID, constant.ReadGroupChatType)
			lc, err := c.db.GetConversation(ctx, conversationID)
			if err != nil {
				log.ZWarn(ctx, "getConversation err", err)
				return
			}
			var latestMsg sdk_struct.MsgStruct
			err = json.Unmarshal([]byte(lc.LatestMsg), &latestMsg)
			if err != nil {
				log.ZError(ctx, "latestMsg,Unmarshal err", err)
			} else {
				//If the sender of the latest message in the conversation
				//happens to be a member of the group whose status has changed,
				//then update the sender's avatar and nickname for the latest message.
				if latestMsg.SendID == args.UserID {
					latestMsg.SenderFaceURL = args.FaceURL
					latestMsg.SenderNickname = args.Nickname
					newLatestMessage := utils.StructToJsonString(latestMsg)
					lc.LatestMsg = newLatestMessage
					err = c.db.UpdateColumnsConversation(ctx, conversationID, map[string]interface{}{"latest_msg": newLatestMessage})
					if err != nil {
						log.ZError(ctx, "updateConversationLatestMsgModel err", err)
					} else {
						var cList []*model_struct.LocalConversation
						cList = append(cList, lc)
						data := utils.StructToJsonStringDefault(cList)
						c.ConversationListener().OnConversationChanged(data)
					}

				}
			}
		}

	case constant.ConChange:
		conversationIDs := node.Args.([]string)
		conversations, err := c.db.GetMultipleConversationDB(ctx, conversationIDs)
		if err != nil {
			log.ZError(ctx, "getMultipleConversationModel err", err)
		} else {
			var newCList []*model_struct.LocalConversation
			for _, v := range conversations {
				if v.LatestMsgSendTime != 0 {
					newCList = append(newCList, v)
				}
			}
			data := utils.StructToJsonStringDefault(newCList)
			log.ZDebug(ctx, "OnConversationChanged", "data", data)
			c.ConversationListener().OnConversationChanged(data)
		}
	case constant.NewCon:
		cidList := node.Args.([]string)
		cLists, err := c.db.GetMultipleConversationDB(ctx, cidList)
		if err != nil {
			log.ZWarn(ctx, "getMultipleConversationModel err", err)
		} else {
			if cLists != nil {
				log.ZDebug(ctx, "getMultipleConversationModel success", "cLists", cLists)
				c.ConversationListener().OnNewConversation(utils.StructToJsonString(cLists))
			}
		}
	case constant.ConChangeDirect:
		cidList := node.Args.(string)
		if logpolicy.Enabled() {
			log.ZInfo(ctx, "ConversationChanged", "cidList", cidList)
		}
		c.ConversationListener().OnConversationChanged(cidList)

	case constant.NewConDirect:
		cidList := node.Args.(string)
		log.ZDebug(ctx, "NewConversation", "cidList", cidList)
		c.ConversationListener().OnNewConversation(cidList)

	}
}

func (c *Conversation) doUpdateMessage(c2v common.Cmd2Value) {
	node := c2v.Value.(common.UpdateMessageNode)
	ctx := c2v.Ctx
	switch node.Action {
	case constant.UpdateMsgFaceUrlAndNickName:
		args := node.Args.(common.UpdateMessageInfo)
		switch args.SessionType {
		case constant.SingleChatType:
			if args.UserID == c.loginUserID {
				conversationIDList, err := c.db.GetAllSingleConversationIDList(ctx)
				if err != nil {
					log.ZError(ctx, "GetAllSingleConversationIDList err", err)
					return
				} else {
					log.ZDebug(ctx, "get single conversationID list", "conversationIDList", conversationIDList)
					for _, conversationID := range conversationIDList {
						err := c.db.UpdateMsgSenderFaceURLAndSenderNickname(ctx, conversationID, args.UserID, args.FaceURL, args.Nickname)
						if err != nil {
							log.ZError(ctx, "UpdateMsgSenderFaceURLAndSenderNickname err", err)
							continue
						}
					}

				}
			} else {
				conversationID := c.getConversationIDBySessionType(args.UserID, constant.SingleChatType)
				err := c.db.UpdateMsgSenderFaceURLAndSenderNickname(ctx, conversationID, args.UserID, args.FaceURL, args.Nickname)
				if err != nil {
					log.ZError(ctx, "UpdateMsgSenderFaceURLAndSenderNickname err", err)
				}

			}
		case constant.ReadGroupChatType:
			conversationID := c.getConversationIDBySessionType(args.GroupID, constant.ReadGroupChatType)
			err := c.db.UpdateMsgSenderFaceURLAndSenderNickname(ctx, conversationID, args.UserID, args.FaceURL, args.Nickname)
			if err != nil {
				log.ZError(ctx, "UpdateMsgSenderFaceURLAndSenderNickname err", err)
			}
		case constant.NotificationChatType:
			conversationID := c.getConversationIDBySessionType(args.UserID, constant.NotificationChatType)
			err := c.db.UpdateMsgSenderFaceURLAndSenderNickname(ctx, conversationID, args.UserID, args.FaceURL, args.Nickname)
			if err != nil {
				log.ZError(ctx, "UpdateMsgSenderFaceURLAndSenderNickname err", err)
			}
		default:
			log.ZError(ctx, "not support sessionType", nil, "args", args)
			return
		}
	}

}

func (c *Conversation) syncData(c2v common.Cmd2Value) error {
	ctx, cancel := syncCommandContext(c2v)
	defer cancel()
	c.startTime = time.Now()
	//clear SubscriptionStatusMap
	//c.user.OnlineStatusCache.DeleteAll()

	// Synchronous sync functions
	syncFuncs := []func(c context.Context) error{}
	if !common.RecoveryMetadataPrepared(ctx) {
		syncFuncs = append(syncFuncs, c.SyncAllConversationHashReadSeqs)
	}

	if err := runRequiredSyncFunctions(ctx, syncFuncs, false); err != nil {
		return err
	}

	// Asynchronous sync functions
	asyncFuncs := []func(c context.Context) error{
		metadataStage("login-user", c.user.SyncLoginUserInfo),
		metadataStage("blacklist", c.relation.SyncAllBlackList),
		metadataStage("groups", c.group.SyncAllJoinedGroupsAndMembersWithLock),
		metadataStage("friends", c.relation.SyncFriendsWithProfilesWithLock),
	}
	if !common.RecoveryMetadataPrepared(ctx) {
		asyncFuncs = append(asyncFuncs, c.IncrSyncConversationsWithLock)
	}

	// These jobs share the cancellable attempt and are joined before yielding
	// to message updates, including jobs holding conversationSyncMutex.
	if err := runRequiredSyncFunctions(ctx, asyncFuncs, true); err != nil {
		return err
	}
	if err := c.reconcileGroupConversationProfiles(ctx); err != nil {
		return err
	}
	return c.flushMissingProfiles(ctx)
}

func runRequiredSyncFunctions(ctx context.Context, funcs []func(context.Context) error, parallel bool) error {
	if !parallel {
		for _, fn := range funcs {
			if err := runSyncFunctionSafely(ctx, fn); err != nil {
				return err
			}
		}
		return nil
	}
	results := make(chan error, len(funcs))
	for _, fn := range funcs {
		go func(run func(context.Context) error) { results <- runSyncFunctionSafely(ctx, run) }(fn)
	}
	var firstError error
	for range funcs {
		if err := <-results; err != nil && firstError == nil {
			firstError = err
		}
	}
	return firstError
}

func runSyncFunctions(ctx context.Context, funcs []func(c context.Context) error, mode int) {
	var wg sync.WaitGroup

	for _, fn := range funcs {
		switch mode {
		case asyncWait:
			wg.Add(1)
			go executeSyncFunction(ctx, fn, &wg)
		case asyncNoWait:
			go executeSyncFunction(ctx, fn, nil)
		case syncWait:
			executeSyncFunction(ctx, fn, nil)
		}
	}

	if mode == asyncWait {
		wg.Wait()
	}
}

func executeSyncFunction(ctx context.Context, fn func(c context.Context) error, wg *sync.WaitGroup) {
	if wg != nil {
		defer wg.Done()
	}

	funcName := runtime.FuncForPC(reflect.ValueOf(fn).Pointer()).Name()
	startTime := time.Now()
	err := runSyncFunctionSafely(ctx, fn)
	duration := time.Since(startTime)
	if err != nil {
		log.ZWarn(ctx, fmt.Sprintf("%s sync error", funcName), err, "duration", duration.String())
	} else {
		log.ZDebug(ctx, fmt.Sprintf("%s completed successfully", funcName), "duration", duration.String())
	}
}

func (c *Conversation) DoConversationChangedNotification(ctx context.Context, msg *sdkws.MsgData) error {
	c.conversationSyncMutex.Lock()
	defer c.conversationSyncMutex.Unlock()

	//var notification sdkws.ConversationChangedNotification
	tips := &sdkws.ConversationUpdateTips{}
	if err := utils.UnmarshalNotificationElem(msg.Content, tips); err != nil {
		log.ZWarn(ctx, "UnmarshalNotificationElem err", err, "msg", msg)
		return err
	}

	err := c.IncrSyncConversations(ctx)
	if err != nil {
		log.ZWarn(ctx, "IncrSyncConversations err", err)
		return err
	}
	return nil
}

func (c *Conversation) DoConversationIsPrivateChangedNotification(ctx context.Context, msg *sdkws.MsgData) error {
	c.conversationSyncMutex.Lock()
	defer c.conversationSyncMutex.Unlock()

	tips := &sdkws.ConversationSetPrivateTips{}
	if err := utils.UnmarshalNotificationElem(msg.Content, tips); err != nil {
		log.ZWarn(ctx, "UnmarshalNotificationElem err", err, "msg", msg)
		return err
	}

	err := c.IncrSyncConversations(ctx)
	if err != nil {
		log.ZWarn(ctx, "IncrSyncConversations err", err)
		return err
	}
	return nil
}

func (c *Conversation) doBusinessNotification(ctx context.Context, msg *sdkws.MsgData) error {
	var n sdk_struct.NotificationElem
	err := utils.JsonStringToStruct(string(msg.Content), &n)
	if err != nil {
		log.ZError(ctx, "unmarshal failed", err, "msg", msg)
		return err

	}
	c.businessListener().OnRecvCustomBusinessMessage(n.Detail)
	return nil
}
