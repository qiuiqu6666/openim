// Copyright © 2023 OpenIM SDK. All rights reserved.
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
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/tools/utils/datautil"

	"github.com/openimsdk/tools/log"
)

func (c *Conversation) SyncAllConversationHashReadSeqs(ctx context.Context) error {
	startTime := time.Now()
	log.ZDebug(ctx, "start SyncConversationHashReadSeqs")

	resp := msg.GetConversationsHasReadAndMaxSeqResp{}
	req := msg.GetConversationsHasReadAndMaxSeqReq{UserID: c.loginUserID}
	err := c.SendReqWaitResp(ctx, &req, constant.GetConvMaxReadSeq, &resp)
	if err != nil {
		log.ZWarn(ctx, "SendReqWaitResp err", err)
		return err
	}
	seqs := resp.Seqs
	log.ZDebug(ctx, "getServerHasReadAndMaxSeqs completed", "duration", time.Since(startTime).String())

	if len(seqs) == 0 {
		return nil
	}
	readSeqs := make(map[string]int64, len(seqs))
	for id, seq := range seqs {
		readSeqs[id] = seq.HasReadSeq
	}
	if err := c.saveReadWatermarks(ctx, readSeqs, true, 0); err != nil {
		return err
	}
	// Protect the local snapshot/update, not the preceding network wait.
	c.conversationSyncMutex.Lock()
	locked := true
	defer func() {
		if locked {
			c.conversationSyncMutex.Unlock()
		}
	}()
	var conversationChangedIDs []string
	var conversationIDsNeedSync []string

	stepStartTime := time.Now()
	conversationsOnLocal, err := c.db.GetAllConversations(ctx)
	if err != nil {
		log.ZWarn(ctx, "get all conversations err", err)
		return err
	}
	log.ZDebug(ctx, "GetAllConversations completed", "duration", time.Since(stepStartTime).String())

	conversationsOnLocalMap := datautil.SliceToMap(conversationsOnLocal, func(e *model_struct.LocalConversation) string {
		return e.ConversationID
	})

	stepStartTime = time.Now()
	for conversationID, v := range seqs {
		var unreadCount int32
		if v.MaxSeq-v.HasReadSeq < 0 {
			unreadCount = 0
			log.ZWarn(ctx, "unread count is less than 0", nil, "conversationID",
				conversationID, "maxSeq", v.MaxSeq, "hasReadSeq", v.HasReadSeq)
		} else {
			unreadCount = int32(v.MaxSeq - v.HasReadSeq)
		}
		if conversation, ok := conversationsOnLocalMap[conversationID]; ok {
			if conversation.UnreadCount != unreadCount {
				if err := c.db.UpdateColumnsConversation(ctx, conversationID, map[string]interface{}{"unread_count": unreadCount}); err != nil {
					log.ZWarn(ctx, "UpdateColumnsConversation err", err, "conversationID", conversationID)
					return err
				}
				conversationChangedIDs = append(conversationChangedIDs, conversationID)
			}
			c.maxSeqRecorder.Set(conversationID, v.MaxSeq)
		} else {
			conversationIDsNeedSync = append(conversationIDsNeedSync, conversationID)
		}
	}
	log.ZDebug(ctx, "Process seqs completed", "duration", time.Since(stepStartTime).String())

	if len(conversationIDsNeedSync) > 0 {
		// Fetch missing metadata without holding the message-storage lock.
		c.conversationSyncMutex.Unlock()
		locked = false
		stepStartTime = time.Now()
		r, err := c.getConversationsByIDsFromServer(ctx, conversationIDsNeedSync)
		if err != nil {
			log.ZWarn(ctx, "getServerConversationsByIDs err", err, "conversationIDs", conversationIDsNeedSync)
			return err
		}
		log.ZDebug(ctx, "getServerConversationsByIDs completed", "duration", time.Since(stepStartTime).String())
		conversationsOnServer := datautil.Batch(ServerConversationToLocal, r.Conversations)
		stepStartTime = time.Now()
		if err := c.batchAddFaceURLAndName(ctx, conversationsOnServer...); err != nil {
			log.ZWarn(ctx, "batchAddFaceURLAndName err", err, "conversationsOnServer", conversationsOnServer)
			return err
		}
		log.ZDebug(ctx, "batchAddFaceURLAndName completed", "duration", time.Since(stepStartTime).String())
		c.conversationSyncMutex.Lock()
		locked = true
		// Another operation may have created a conversation during the fetch.
		// Its latest message and local settings must not be replaced by this
		// metadata-only response.
		current, err := c.db.GetMultipleConversationDB(ctx, conversationIDsNeedSync)
		if err != nil {
			return err
		}
		existing := make(map[string]struct{}, len(current))
		for _, conversation := range current {
			existing[conversation.ConversationID] = struct{}{}
		}
		missing := conversationsOnServer[:0]
		for _, conversation := range conversationsOnServer {
			if _, present := existing[conversation.ConversationID]; !present {
				missing = append(missing, conversation)
			}
		}
		conversationsOnServer = missing

		for _, conversation := range conversationsOnServer {
			var unreadCount int32
			v, ok := seqs[conversation.ConversationID]
			if !ok {
				continue
			}
			if v.MaxSeq-v.HasReadSeq < 0 {
				unreadCount = 0
				log.ZWarn(ctx, "unread count is less than 0", nil, "server seq", v, "conversation", conversation)
			} else {
				unreadCount = int32(v.MaxSeq - v.HasReadSeq)
			}
			conversation.UnreadCount = unreadCount
		}

		stepStartTime = time.Now()
		err = c.db.BatchInsertConversationList(ctx, conversationsOnServer)
		if err != nil {
			log.ZWarn(ctx, "BatchInsertConversationList err", err, "conversationsOnServer", conversationsOnServer)
			return err
		}
		log.ZDebug(ctx, "BatchInsertConversationList completed", "duration", time.Since(stepStartTime).String())
		for _, conversation := range conversationsOnServer {
			if v, ok := seqs[conversation.ConversationID]; ok {
				c.maxSeqRecorder.Set(conversation.ConversationID, v.MaxSeq)
			}
		}
	}
	c.conversationSyncMutex.Unlock()
	locked = false

	log.ZDebug(ctx, "update conversations", "conversations", conversationChangedIDs)
	if len(conversationChangedIDs) > 0 {
		stepStartTime = time.Now()
		if err := c.notifySyncedConversations(ctx, conversationChangedIDs); err != nil {
			return err
		}
		log.ZDebug(ctx, "TriggerCmdUpdateConversation completed", "duration", time.Since(stepStartTime).String())
	}

	log.ZDebug(ctx, "SyncAllConversationHashReadSeqs completed", "totalDuration", time.Since(startTime).String())
	return nil
}
