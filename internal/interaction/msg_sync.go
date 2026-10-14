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

package interaction

import (
	"context"
	"errors"
	"fmt"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/msg"
	"github.com/openimsdk/tools/errs"

	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/log"
)

const (
	connectPullNums = 1
	defaultPullNums = 10
	SplitPullMsgNum = 100

	pullMsgGoroutineLimit = 10
)

// MsgSyncer is a central hub for message relay, responsible for sequential message gap pulling,
// handling network events, and managing app foreground and background events.
type MsgSyncer struct {
	loginUserID          string                // login user ID
	longConnMgr          *LongConnMgr          // long connection manager
	recvCh               chan common.Cmd2Value // channel for receiving push messages and the maximum SEQ number
	conversationCh       chan common.Cmd2Value // storage and session triggering
	syncedMaxSeqs        map[string]int64      // map of the maximum synced SEQ numbers for all group IDs
	syncedMaxSeqsLock    sync.RWMutex          // syncedMaxSeqs map lock
	checkpoints          map[string]messageCheckpoint
	checkpointIDs        map[string]bool
	recoveryReadSeqReady bool
	pendingReadReconcile bool
	initialMetadataReady bool
	db                   db_interface.DataBase // data store
	syncTimes            int                   // times of sync
	ctx                  context.Context       // context
	reinstalled          bool                  //true if the app was uninstalled and reinstalled
	isSyncing            bool                  // indicates whether data is being synced
	isSyncingLock        sync.Mutex            // lock for syncing state

}

// NewMsgSyncer creates a new instance of the message synchronizer.
func NewMsgSyncer(ctx context.Context, conversationCh, recvCh chan common.Cmd2Value,
	loginUserID string, longConnMgr *LongConnMgr, db db_interface.DataBase, syncTimes int) (*MsgSyncer, error) {
	m := &MsgSyncer{
		loginUserID:    loginUserID,
		longConnMgr:    longConnMgr,
		recvCh:         recvCh,
		conversationCh: conversationCh,
		ctx:            ctx,
		syncedMaxSeqs:  make(map[string]int64),
		db:             db,
		syncTimes:      syncTimes,
	}
	if err := m.loadSeq(ctx); err != nil {
		log.ZError(ctx, "loadSeq err", err)
		return nil, err
	}
	return m, nil
}

// seq The db reads the data to the memory,set syncedMaxSeqs
func (m *MsgSyncer) loadSeq(ctx context.Context) error {
	conversationIDList, err := m.db.GetAllConversationIDList(ctx)
	if err != nil {
		log.ZError(ctx, "get conversation id list failed", err)
		return err
	}

	version, err := m.db.GetAppSDKVersion(ctx)
	if err != nil && !errors.Is(err, errs.ErrRecordNotFound) {
		return err
	}
	if (version != nil && !version.Installed) || (version == nil && len(conversationIDList) == 0) {
		m.reinstalled = true
	}

	// TODO With a large number of sessions(10w), this could potentially cause blocking and needs optimization.

	type SyncedSeq struct {
		ConversationID string
		MaxSyncedSeq   int64
		Err            error
	}

	partSize := 20
	currency := (len(conversationIDList)-1)/partSize + 1
	if len(conversationIDList) == 0 {
		currency = 0
	}
	var wg sync.WaitGroup
	resultMaps := make([]map[string]SyncedSeq, currency)

	for i := 0; i < currency; i++ {
		wg.Add(1)
		start := i * partSize
		end := start + partSize
		if i == currency-1 {
			end = len(conversationIDList)
		}

		resultMaps[i] = make(map[string]SyncedSeq)

		go func(i, start, end int) {
			defer wg.Done()
			for _, v := range conversationIDList[start:end] {
				maxSyncedSeq, err := m.db.CheckConversationNormalMsgSeq(ctx, v)
				resultMaps[i][v] = SyncedSeq{
					ConversationID: v,
					MaxSyncedSeq:   maxSyncedSeq,
					Err:            err,
				}
			}
		}(i, start, end)
	}

	wg.Wait()

	// merge map
	for _, resultMap := range resultMaps {
		for k, v := range resultMap {
			if v.Err != nil {
				log.ZError(ctx, "get group normal seq failed", errs.Wrap(v.Err), "conversationID", k)
				continue
			}
			m.syncedMaxSeqs[k] = v.MaxSyncedSeq
		}
	}
	notificationSeqs, err := m.db.GetNotificationAllSeqs(ctx)
	if err != nil {
		log.ZError(ctx, "get notification seq failed", err)
		return err
	}
	for _, notificationSeq := range notificationSeqs {
		m.syncedMaxSeqs[notificationSeq.ConversationID] = notificationSeq.Seq
	}
	log.ZDebug(ctx, "loadSeq", "syncedMaxSeqs", m.syncedMaxSeqs)
	return m.loadMessageCheckpoints(ctx, conversationIDList)
}

// DoListener Listen to the message pipe of the message synchronizer
// and process received and pushed messages
func (m *MsgSyncer) DoListener(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			err := fmt.Sprintf("panic: %+v\n%s", r, debug.Stack())

			log.ZWarn(ctx, "DoListener panic", nil, "panic info", err)
		}
	}()
	ticker := time.NewTicker(messageSeqReconciliationInterval)
	defer ticker.Stop()
	m.listenWithReconciliation(ctx, ticker.C)
}

func (m *MsgSyncer) handlePushMsgAndEventSafely(cmd common.Cmd2Value) {
	defer func() {
		if failure := recover(); failure != nil {
			m.finishSync()
			log.ZWarn(cmd.Ctx, "message sync command panic", nil, "panic info",
				fmt.Sprintf("%v\n%s", failure, debug.Stack()))
			common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
		}
	}()
	m.handlePushMsgAndEvent(cmd)
}

// get seqs need sync interval
func (m *MsgSyncer) getSeqsNeedSync(syncedMaxSeq, maxSeq int64) []int64 {
	var seqs []int64
	for i := syncedMaxSeq + 1; i <= maxSeq; i++ {
		seqs = append(seqs, i)
	}
	return seqs
}

// recv msg from
func (m *MsgSyncer) handlePushMsgAndEvent(cmd common.Cmd2Value) {
	switch cmd.Cmd {
	case constant.CmdConnSuccesss:
		log.ZInfo(cmd.Ctx, "recv long conn mgr connected", "cmd", cmd.Cmd, "value", cmd.Value)
		if m.startSync() {
			m.doConnected(cmd.Ctx)
		} else {
			log.ZWarn(cmd.Ctx, "syncing, ignore connected event", nil, "cmd", cmd.Cmd, "value", cmd.Value)
		}
	case constant.CmdWakeUpDataSync:
		log.ZInfo(cmd.Ctx, "app wake up, start sync msgs", "cmd", cmd.Cmd, "value", cmd.Value)
		if m.startSync() {
			m.doWakeupDataSync(cmd.Ctx)
		} else {
			log.ZWarn(cmd.Ctx, "syncing, ignore wake up event", nil, "cmd", cmd.Cmd, "value", cmd.Value)

		}
	case constant.CmdIMMessageSync:
		log.ZInfo(cmd.Ctx, "manually trigger IM message synchronization", "cmd", cmd.Cmd, "value", cmd.Value)
		m.doIMMessageSync(cmd.Ctx)
	case cmdReconcileMessageSeq:
		m.doMessageSeqReconciliation(cmd.Ctx)

	case constant.CmdPushMsg:
		m.doPushMsg(cmd.Ctx, cmd.Value.(*sdkws.PushMessages))
	}
}

func (m *MsgSyncer) compareSeqsAndBatchSync(ctx context.Context, maxSeqToSync map[string]int64, pullNums int64) error {
	// Persist targets before any writes, then merge obligations left by an
	// interrupted attempt even if the newest server observation is stale.
	targets := make(map[string]int64, len(maxSeqToSync))
	ids := make([]string, 0, len(maxSeqToSync))
	for id := range maxSeqToSync {
		if !IsNotification(id) {
			ids = append(ids, id)
		}
	}
	if err := m.registerMessageCheckpointIDs(ctx, ids); err != nil {
		return err
	}
	for id, seq := range maxSeqToSync {
		if err := m.rememberMessageTarget(ctx, id, seq); err != nil {
			return err
		}
		targets[id] = seq
	}
	for id, state := range m.checkpoints {
		targets[id] = max(targets[id], state.Target)
	}
	maxSeqToSync = targets
	needSyncSeqMap := make(map[string][2]int64)
	//when app reinstalled do not pull notifications messages.
	if m.reinstalled {
		notificationsSeqMap := make(map[string]int64)
		messagesSeqMap := make(map[string]int64)
		for conversationID, seq := range maxSeqToSync {
			if IsNotification(conversationID) {
				if seq != 0 { // seq is 0, no need to sync
					// Match the durable monotonic bootstrap baseline on retry.
					// Otherwise a stale maximum rewinds the in-memory cursor even
					// though SQLite correctly retained the newer notification seq.
					notificationsSeqMap[conversationID] = max(seq, m.syncedMaxSeqs[conversationID])
				}
			} else {
				messagesSeqMap[conversationID] = seq
			}
		}

		var notificationSeqs []*model_struct.NotificationSeqs

		for conversationID, seq := range notificationsSeqMap {
			notificationSeqs = append(notificationSeqs, &model_struct.NotificationSeqs{
				ConversationID: conversationID,
				Seq:            seq,
			})
		}

		if len(notificationSeqs) > 0 {
			err := m.db.BatchInsertNotificationSeq(ctx, notificationSeqs)
			if err != nil {
				log.ZWarn(ctx, "BatchInsertNotificationSeq err", err)
				return err
			}
		}
		for conversationID, seq := range notificationsSeqMap {
			m.syncedMaxSeqs[conversationID] = seq
		}

		for conversationID, maxSeq := range messagesSeqMap {
			if syncedMaxSeq, ok := m.syncedMaxSeqs[conversationID]; ok {
				if maxSeq > syncedMaxSeq {
					needSyncSeqMap[conversationID] = [2]int64{syncedMaxSeq + 1, maxSeq}
				}
			} else {
				needSyncSeqMap[conversationID] = [2]int64{0, maxSeq}
			}
		}
		if err := m.syncAndTriggerReinstallMsgs(ctx, needSyncSeqMap, pullNums); err != nil {
			return err
		}
		if err := m.db.SetAppSDKVersion(ctx, &model_struct.LocalAppSDKVersion{Installed: true}); err != nil {
			return err
		}
		m.reinstalled = false
	} else {
		for conversationID, maxSeq := range maxSeqToSync {
			if syncedMaxSeq, ok := m.syncedMaxSeqs[conversationID]; ok {
				if maxSeq > syncedMaxSeq {
					needSyncSeqMap[conversationID] = [2]int64{syncedMaxSeq + 1, maxSeq}
				}
			} else {
				if maxSeq != 0 { // seq is 0, no need to sync
					needSyncSeqMap[conversationID] = [2]int64{0, maxSeq}
				}
			}
		}
		return m.syncAndTriggerMsgs(ctx, needSyncSeqMap, pullNums)
	}
	return nil
}

// startSync checks if the sync is already in progress.
// If syncing is in progress, it returns false. Otherwise, it starts syncing and returns true.
func (m *MsgSyncer) startSync() bool {
	m.isSyncingLock.Lock()
	defer m.isSyncingLock.Unlock()

	if m.isSyncing {
		// If already syncing, return false
		return false
	}

	// Set syncing to true and start the sync
	m.isSyncing = true

	return true
}

func (m *MsgSyncer) finishSync() {
	m.isSyncingLock.Lock()
	m.isSyncing = false
	m.isSyncingLock.Unlock()
}

func (m *MsgSyncer) doPushMsg(ctx context.Context, push *sdkws.PushMessages) {
	if m.reinstalled && !m.initialMetadataReady {
		// Keep message targets durable, but do not deliver against missing
		// first-login metadata or acknowledge unseen notification state.
		for id, batch := range push.Msgs {
			for _, row := range batch.Msgs {
				if err := m.rememberMessageTarget(ctx, id, row.Seq); err != nil {
					log.ZWarn(ctx, "persist initial push target failed", err)
					return
				}
			}
		}
		select {
		case m.recvCh <- common.Cmd2Value{Ctx: m.ctx, Cmd: constant.CmdConnSuccesss}:
		default: // The next foreground reconciliation retries initialization.
		}
		return
	}
	log.ZDebug(ctx, "push msgs", "push", push, "syncedMaxSeqs", m.syncedMaxSeqs)
	m.pushTriggerAndSync(ctx, push.Msgs, m.triggerConversation)
	m.pushTriggerAndSync(ctx, push.NotificationMsgs, m.triggerNotification)
}

func (m *MsgSyncer) pushTriggerAndSync(ctx context.Context, pushMessages map[string]*sdkws.PullMsgs,
	triggerFunc func(ctx context.Context, msgs map[string]*sdkws.PullMsgs) error) {
	if len(pushMessages) == 0 {
		return
	}

	needSyncSeqMap := make(map[string][2]int64)
	res := make(map[string]*sdkws.PullMsgs)

	for conversationID, msgs := range pushMessages {
		var (
			lastSeq     int64
			storageMsgs []*sdkws.MsgData
		)
		contiguous := true
		expected := m.syncedMaxSeqs[conversationID] + 1
		seen := make(map[int64]bool, len(msgs.Msgs))

		for _, msg := range msgs.Msgs {
			if msg.Seq == 0 {
				_ = triggerFunc(ctx, map[string]*sdkws.PullMsgs{
					conversationID: {Msgs: []*sdkws.MsgData{msg}},
				})
				continue
			}
			if msg.Seq <= m.syncedMaxSeqs[conversationID] || seen[msg.Seq] {
				continue
			}
			seen[msg.Seq] = true
			if !IsNotification(conversationID) && m.messageAlreadyCovered(conversationID, msg.Seq) {
				continue
			}
			lastSeq = max(lastSeq, msg.Seq)
			if msg.Seq != expected {
				contiguous = false
			}
			expected++
			storageMsgs = append(storageMsgs, msg)
		}

		if len(storageMsgs) == 0 {
			continue
		}
		if err := m.rememberMessageTarget(ctx, conversationID, lastSeq); err != nil {
			log.ZError(ctx, "persist push recovery target failed", err)
			common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
			return
		}

		if contiguous || !IsNotification(conversationID) {
			log.ZDebug(ctx, "trigger msgs", "conversationID", conversationID, "msgs", storageMsgs)
			res[conversationID] = &sdkws.PullMsgs{Msgs: storageMsgs}
		}
		if !contiguous && lastSeq > m.syncedMaxSeqs[conversationID] {
			if !IsNotification(conversationID) {
				m.pendingReadReconcile = true
			}
			// must pull message when message type is notification
			needSyncSeqMap[conversationID] = [2]int64{
				m.syncedMaxSeqs[conversationID] + 1,
				lastSeq,
			}
		}
	}

	if len(res) > 0 {
		if err := triggerFunc(ctx, res); err != nil {
			log.ZError(ctx, "message commit failed", err)
			common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
			return
		}
		for conversationID, msgs := range res {
			var commitErr error
			if IsNotification(conversationID) {
				commitErr = m.commitMessageCheckpoint(ctx, conversationID, msgs.Msgs[len(msgs.Msgs)-1].Seq)
			} else {
				var covered [][2]int64
				for _, row := range msgs.Msgs {
					covered = append(covered, [2]int64{row.Seq, row.Seq})
				}
				commitErr = m.commitMessageCoverage(ctx, conversationID, covered)
			}
			if err := commitErr; err != nil {
				log.ZError(ctx, "persist push checkpoint failed", err)
				common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
				return
			}
		}
	}
	if len(needSyncSeqMap) > 0 && m.recvCh != nil {
		deferNormal := true
		for id := range needSyncSeqMap {
			if IsNotification(id) {
				deferNormal = false
			}
		}
		if deferNormal {
			// The journal already contains these targets. Let the interruptible
			// background scheduler own large gaps rather than blocking live ingress.
			select {
			case m.recvCh <- common.Cmd2Value{Ctx: m.ctx, Cmd: constant.CmdIMMessageSync}:
			default:
			}
			return
		}
	}
	if err := m.syncAndTriggerMsgs(ctx, needSyncSeqMap, defaultPullNums); err != nil {
		log.ZError(ctx, "message gap sync failed", err)
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
	}
}

// Called after successful reconnection to synchronize the latest message
func (m *MsgSyncer) doConnected(ctx context.Context) {
	defer m.finishSync()
	reinstalled := m.reinstalled
	if reinstalled {
		m.initialMetadataReady = false
		if err := m.db.SetAppSDKVersion(ctx, &model_struct.LocalAppSDKVersion{Installed: false}); err != nil {
			log.ZWarn(ctx, "initial sync failed", err, "stage", "persist-initialization")
			common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
			return
		}
		if err := m.triggerSyncStart(ctx, constant.AppDataSyncStart); err != nil {
			log.ZWarn(ctx, "initial sync failed", err, "stage", "metadata-receipt")
			common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
			return
		}
		m.initialMetadataReady = true
	} else {
		if err := m.triggerSyncStart(ctx, constant.MsgSyncBegin); err != nil {
			common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
			return
		}
	}
	var resp sdkws.GetMaxSeqResp
	if err := m.longConnMgr.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{UserID: m.loginUserID}, constant.GetNewestSeq, &resp); err != nil {
		log.ZError(m.ctx, "get max seq error", err)
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
		return
	} else {
		log.ZDebug(m.ctx, "get max seq success", "resp", resp.MaxSeqs)
	}
	if err := m.compareSeqsAndBatchSync(ctx, resp.MaxSeqs, connectPullNums); err != nil {
		log.ZWarn(ctx, "connected message sync failed", err, "stage", "pull-storage-checkpoint", "initial", reinstalled)
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
		return
	}
	if reinstalled {
		common.TriggerCmdSyncFlag(m.ctx, constant.AppDataSyncFinish, m.conversationCh)
	} else {
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncEnd, m.conversationCh)
	}
}

func (m *MsgSyncer) doWakeupDataSync(ctx context.Context) {
	// Terminal flags are queued on the login-session context (m.ctx). The
	// scheduler cancels ctx on return, before the conversation worker may read
	// the flag; using ctx there would strand clients in SyncBegin forever.
	defer m.finishSync()
	if m.reinstalled {
		m.doConnected(ctx)
		return
	}
	if err := m.triggerSyncStart(ctx, constant.MsgSyncBegin); err != nil {
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
		return
	}
	var resp sdkws.GetMaxSeqResp
	if err := m.longConnMgr.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{UserID: m.loginUserID}, constant.GetNewestSeq, &resp); err != nil {
		log.ZError(m.ctx, "get max seq error", err)
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
		return
	} else {
		log.ZDebug(m.ctx, "get max seq success", "resp", resp.MaxSeqs)
	}
	if err := m.compareSeqsAndBatchSync(ctx, resp.MaxSeqs, defaultPullNums); err != nil {
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
		return
	}
	common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncEnd, m.conversationCh)
}

func (m *MsgSyncer) doIMMessageSync(ctx context.Context) {
	if m.reinstalled {
		if m.startSync() {
			m.doConnected(ctx)
		}
		return
	}
	var resp sdkws.GetMaxSeqResp
	if err := m.longConnMgr.SendReqWaitResp(ctx, &sdkws.GetMaxSeqReq{UserID: m.loginUserID}, constant.GetNewestSeq, &resp); err != nil {
		log.ZError(m.ctx, "get max seq error", err)
		return
	} else {
		log.ZDebug(m.ctx, "get max seq success", "resp", resp.MaxSeqs)
	}
	if err := m.compareSeqsAndBatchSync(ctx, resp.MaxSeqs, defaultPullNums); err != nil {
		common.TriggerCmdSyncFlag(m.ctx, constant.MsgSyncFailed, m.conversationCh)
	}
}

func IsNotification(conversationID string) bool {
	return strings.HasPrefix(conversationID, "n_")
}

func (m *MsgSyncer) syncAndTriggerMsgs(ctx context.Context, seqMap map[string][2]int64, syncMsgNum int64) error {
	return m.syncCompleteMessageRanges(ctx, seqMap, false)
}

func (m *MsgSyncer) syncAndTriggerReinstallMsgs(ctx context.Context, seqMap map[string][2]int64, syncMsgNum int64) error {
	return m.syncCompleteMessageRanges(ctx, seqMap, true)
}
func (m *MsgSyncer) checkMessagesAndGetLastMessage(ctx context.Context, messages map[string]*sdkws.PullMsgs) error {
	var conversationIDs []string

	for conversationID, message := range messages {
		allInValid := true
		for _, data := range message.Msgs {
			if data.Status < constant.MsgStatusHasDeleted {
				allInValid = false
				break
			}
		}
		if allInValid {
			conversationIDs = append(conversationIDs, conversationID)
		}
	}
	if len(conversationIDs) > 0 {
		resp, err := m.fetchLatestValidMessages(ctx, conversationIDs)
		if err != nil {
			log.ZError(ctx, "fetchLatestValidMessages", err, "conversationIDs", conversationIDs)
			return err
		}
		for conversationID, message := range resp.Msgs {
			messages[conversationID] = &sdkws.PullMsgs{Msgs: []*sdkws.MsgData{message}}
		}
	}
	return nil
}

func (m *MsgSyncer) splitSeqs(split int, seqsNeedSync []int64) (splitSeqs [][]int64) {
	if len(seqsNeedSync) <= split {
		splitSeqs = append(splitSeqs, seqsNeedSync)
		return
	}
	for i := 0; i < len(seqsNeedSync); i += split {
		end := i + split
		if end > len(seqsNeedSync) {
			end = len(seqsNeedSync)
		}
		splitSeqs = append(splitSeqs, seqsNeedSync[i:end])
	}
	return
}

func (m *MsgSyncer) pullMsgBySeqRange(ctx context.Context, seqMap map[string][2]int64, syncMsgNum int64, order ...sdkws.PullOrder) (resp *sdkws.PullMessageBySeqsResp, err error) {
	log.ZDebug(ctx, "pullMsgBySeqRange", "seqMap", seqMap, "syncMsgNum", syncMsgNum)

	req := sdkws.PullMessageBySeqsReq{UserID: m.loginUserID}
	// The caller supplies one complete bounded page. Never silently crop it.
	if len(order) > 0 {
		req.Order = order[0]
	}
	for conversationID, seqs := range seqMap {
		req.SeqRanges = append(req.SeqRanges, &sdkws.SeqRange{
			ConversationID: conversationID,
			Begin:          seqs[0],
			End:            seqs[1],
			Num:            syncMsgNum,
		})
	}
	resp = &sdkws.PullMessageBySeqsResp{}
	if err := m.longConnMgr.SendReqWaitResp(ctx, &req, constant.PullMsgByRange, resp); err != nil {
		return nil, err
	}
	return resp, nil
}

func (m *MsgSyncer) fetchLatestValidMessages(ctx context.Context, conversationID []string) (resp *msg.GetLastMessageResp, err error) {
	log.ZDebug(ctx, "fetchLatestValidMessages", "conversationID", conversationID)

	req := msg.GetLastMessageReq{
		UserID:          m.loginUserID,
		ConversationIDs: conversationID,
	}
	resp = &msg.GetLastMessageResp{}
	if err := m.longConnMgr.SendReqWaitResp(ctx, &req, constant.PullConvLastMessage, resp); err != nil {
		return nil, err
	}
	return resp, nil
}

// synchronizes messages by SEQs.
func (m *MsgSyncer) syncMsgBySeqs(ctx context.Context, conversationID string, seqsNeedSync []int64) (allMsgs []*sdkws.MsgData, err error) {
	pullMsgReq := sdkws.PullMessageBySeqsReq{}
	pullMsgReq.UserID = m.loginUserID
	split := constant.SplitPullMsgNum
	seqsList := m.splitSeqs(split, seqsNeedSync)
	for i := 0; i < len(seqsList); {
		var pullMsgResp sdkws.PullMessageBySeqsResp
		err := m.longConnMgr.SendReqWaitResp(ctx, &pullMsgReq, constant.PullMsgByRange, &pullMsgResp)
		if err != nil {
			log.ZError(ctx, "syncMsgFromServerSplit err", err, "pullMsgReq", &pullMsgReq)
			continue
		}
		i++
		allMsgs = append(allMsgs, pullMsgResp.Msgs[conversationID].Msgs...)
	}
	return allMsgs, nil
}

// triggers a conversation with a new message.
func (m *MsgSyncer) triggerConversation(ctx context.Context, msgs map[string]*sdkws.PullMsgs) error {
	if len(msgs) > 0 {
		err := common.SendCmdWithReceipt(ctx, common.Cmd2Value{
			Cmd:   constant.CmdNewMsgCome,
			Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: msgs, Recovery: true},
		}, m.conversationCh)
		if err != nil {
			log.ZError(ctx, "triggerCmdNewMsgCome err", err, "msgs", msgs)
		}
		log.ZDebug(ctx, "triggerConversation", "msgs", msgs)
		return err
	} else {
		log.ZDebug(ctx, "triggerConversation is nil", "msgs", msgs)
	}
	return nil
}

// triggers a conversation with a new message.
func (m *MsgSyncer) triggerReinstallConversation(ctx context.Context, msgs map[string]*sdkws.PullMsgs, total int, notifyConversations ...bool) (err error) {
	if len(msgs) > 0 {
		err = common.SendCmdWithReceipt(ctx, common.Cmd2Value{
			Cmd:   constant.CmdMsgSyncInReinstall,
			Value: sdk_struct.CmdMsgSyncInReinstall{Msgs: msgs, Total: total, NotifyConversations: len(notifyConversations) > 0 && notifyConversations[0]},
		}, m.conversationCh)
		if err != nil {
			log.ZError(ctx, "triggerCmdNewMsgCome err", err, "msgs", msgs)
		}
		log.ZDebug(ctx, "triggerConversation", "msgs", msgs)
		return err
	} else {
		log.ZDebug(ctx, "triggerConversation is nil", "msgs", msgs)
	}
	return nil
}

func (m *MsgSyncer) triggerNotification(ctx context.Context, msgs map[string]*sdkws.PullMsgs) error {
	if len(msgs) > 0 {
		return common.SendCmdWithReceipt(ctx, common.Cmd2Value{
			Cmd:   constant.CmdNotification,
			Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: msgs},
		}, m.conversationCh)
	} else {
		log.ZDebug(ctx, "triggerNotification is nil", "notifications", msgs)
	}
	return nil

}
