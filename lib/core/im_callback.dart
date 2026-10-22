import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';

import 'controller/app_controller.dart';
import 'conversation_reads/conversation_read_request.dart';
import 'conversation_reads/conversation_batch_read_api.dart';
import 'session/message_events.dart';
import '../services/chat_history_cache.dart';
import '../services/fund/fund_refresh_events.dart';
import '../pages/ai_assistant/streaming/diagnostics/assistant_stream_log.dart';

enum IMSdkStatus {
  connectionFailed,
  connecting,
  connectionSucceeded,
  syncStart,
  synchronizing,
  syncEnded,
  syncFailed,
  syncProgress,
}

enum KickoffType {
  kickedOffline,
  userTokenInvalid,
  userTokenExpired,
}

mixin IMCallback {
  final initLogic = Get.find<AppController>();

  final revokedMessages = PublishSubject<RevokedInfo>();
  final deletedMessages = PublishSubject<Message>();

  /// Observers share incoming SDK messages without replacing the chat callback.
  final receivedMessages = PublishSubject<Message>();
  final chatMessageEvents = PublishSubject<ChatMessageEvent>(sync: true);
  final c2cReadReceipts = PublishSubject<List<ReadReceiptInfo>>(sync: true);
  final historyRecoverySignals = PublishSubject<void>();

  void publishChatMessage(Message message, ChatMessageSource source) =>
      chatMessageEvents.addSafely(ChatMessageEvent(message, source));

  void publishLocalChatMessage(Message message) {
    publishChatMessage(message, ChatMessageSource.local);
    onRecvNewMessage?.call(message);
  }

  Function(RevokedInfo info)? onRecvMessageRevoked;

  Function(List<ReadReceiptInfo> list)? onRecvC2CReadReceipt;

  Function(Message msg)? onRecvNewMessage;

  Function(Message msg)? onRecvOfflineMessage;

  Function(String msgId, int progress)? onMsgSendProgress;
  final messageUploadProgress = PublishSubject<MsgStreamEv<int>>();

  Function(BlacklistInfo u)? onBlacklistAdd;

  Function(BlacklistInfo u)? onBlacklistDeleted;

  Function(int current, int size)? onUploadProgress;

  // Incremental notifications must never replay into a later account or route.
  // Each screen obtains its initial snapshot from the current SDK session.
  final conversationAddedSubject = PublishSubject<List<ConversationInfo>>();

  final conversationChangedSubject = PublishSubject<List<ConversationInfo>>();

  final conversationReadRequestSubject =
      PublishSubject<ConversationReadRequest>(sync: true);
  final conversationEntryReadSubject =
      PublishSubject<BatchReadTarget>(sync: true);

  final unreadMsgCountEventSubject = PublishSubject<int>();

  final friendApplicationChangedSubject =
      PublishSubject<FriendApplicationInfo>();
  final friendApplicationAddedSubject =
      PublishSubject<FriendApplicationInfo>(sync: true);
  final groupApplicationAddedSubject =
      PublishSubject<GroupApplicationInfo>(sync: true);

  final friendAddSubject = PublishSubject<FriendInfo>();

  final friendDelSubject = PublishSubject<FriendInfo>();

  final friendInfoChangedSubject = PublishSubject<FriendInfo>();

  final blacklistChangedSubject = PublishSubject<BlacklistInfo>();

  final selfInfoUpdatedSubject = PublishSubject<UserInfo>();

  final userStatusChangedSubject = PublishSubject<UserStatusInfo>();

  final groupInfoUpdatedSubject = PublishSubject<GroupInfo>();

  final groupApplicationChangedSubject = PublishSubject<GroupApplicationInfo>();

  final initializedSubject = PublishSubject<bool>();

  final memberAddedSubject = PublishSubject<GroupMembersInfo>();

  final memberDeletedSubject = PublishSubject<GroupMembersInfo>();

  final memberInfoChangedSubject = PublishSubject<GroupMembersInfo>();

  final joinedGroupDeletedSubject = PublishSubject<GroupInfo>();

  final joinedGroupAddedSubject = PublishSubject<GroupInfo>();

  final onKickedOfflineSubject = PublishSubject<KickoffType>();

  final imSdkStatusSubject =
      ReplaySubject<({IMSdkStatus status, bool reInstall, int? progress})>(
          maxSize: 1);

  ({IMSdkStatus status, bool reInstall, int? progress})? _initialSyncState;
  String? _initialSyncUserID;
  ({IMSdkStatus status, bool reInstall, int? progress})? get initialSyncState =>
      _initialSyncUserID == DataSp.userID ? _initialSyncState : null;

  IMSdkStatus? _currentSdkStatus;
  IMSdkStatus? get currentSdkStatus => _currentSdkStatus;
  (String?, String?)? _notificationReadySession;
  // History synchronization is not authentication. An authenticated profile
  // can enable live alerts even if history recovery never reaches syncEnded.
  bool get notificationSessionReady =>
      _notificationReadySession != null &&
      _notificationReadySession == (DataSp.userID, DataSp.chatToken);

  void resetNotificationReadiness() => _notificationReadySession = null;

  void markNotificationSessionReady(String account, String? token) {
    if (account.isNotEmpty &&
        token?.isNotEmpty == true &&
        account == DataSp.userID &&
        token == DataSp.chatToken) {
      _notificationReadySession = (account, token);
    }
  }

  IMSdkStatus? _connectionStatus;
  IMSdkStatus? get currentConnectionStatus => _connectionStatus;

  final imSdkStatusPublishSubject =
      PublishSubject<({IMSdkStatus status, bool reInstall, int? progress})>();

  final inputStateChangedSubject = PublishSubject<InputStatusChangedData>();

  final customBusinessMessageSubject = PublishSubject<String>();

  void imSdkStatus(IMSdkStatus status,
      {bool reInstall = false, int? progress}) {
    if (_initialSyncUserID != DataSp.userID) {
      _initialSyncState = null;
      _initialSyncUserID = DataSp.userID;
    }
    if (status == IMSdkStatus.syncStart) {
      _initialSyncState =
          reInstall ? (status: status, reInstall: true, progress: 0) : null;
    } else if (status == IMSdkStatus.syncProgress &&
        _initialSyncState != null) {
      reInstall = true;
      _initialSyncState = (status: status, reInstall: true, progress: progress);
    } else if (status == IMSdkStatus.syncEnded ||
        status == IMSdkStatus.syncFailed) {
      _initialSyncState = null;
    }
    _currentSdkStatus = status;
    if (status == IMSdkStatus.syncEnded &&
        DataSp.userID?.isNotEmpty == true &&
        DataSp.chatToken?.isNotEmpty == true) {
      _notificationReadySession = (DataSp.userID, DataSp.chatToken);
    }
    if (status == IMSdkStatus.connecting ||
        status == IMSdkStatus.connectionFailed ||
        status == IMSdkStatus.connectionSucceeded) {
      _connectionStatus = status;
    }
    imSdkStatusSubject
        .add((status: status, reInstall: reInstall, progress: progress));
    imSdkStatusPublishSubject
        .add((status: status, reInstall: reInstall, progress: progress));
    if (status == IMSdkStatus.syncEnded) {
      initLogic.onApplicationSessionReady(authenticated: true);
    }
  }

  void kickedOffline() {
    resetNotificationReadiness();
    onKickedOfflineSubject.add(KickoffType.kickedOffline);
  }

  void userTokenInvalid() {
    resetNotificationReadiness();
    onKickedOfflineSubject.add(KickoffType.userTokenInvalid);
  }

  void userTokenExpired() {
    resetNotificationReadiness();
    onKickedOfflineSubject.add(KickoffType.userTokenExpired);
  }

  void selfInfoUpdated(UserInfo user) {
    selfInfoUpdatedSubject.addSafely(user);
  }

  void userStausChanged(UserStatusInfo u) {
    userStatusChangedSubject.addSafely(u);
  }

  void uploadLogsProgress(int current, int size) {
    onUploadProgress?.call(current, size);
  }

  void recvMessageRevoked(RevokedInfo info) {
    ChatHistoryCache.revokeMessage(OpenIM.iMManager.userID, info);
    revokedMessages.addSafely(info);
    onRecvMessageRevoked?.call(info);
  }

  void messageDeleted(Message message) {
    ChatHistoryCache.removeMessage(
        OpenIM.iMManager.userID, message.clientMsgID);
    deletedMessages.addSafely(message);
  }

  void recvC2CMessageReadReceipt(List<ReadReceiptInfo> list) {
    c2cReadReceipts.addSafely(list);
    onRecvC2CReadReceipt?.call(list);
  }

  void recvNewMessage(Message msg) {
    ChatHistoryCache.receivedMessage();
    AssistantStreamLog.received(msg,
        source: 'normal',
        hasReceiver: chatMessageEvents.hasListener || onRecvNewMessage != null);
    receivedMessages.addSafely(msg);
    publishChatMessage(msg, ChatMessageSource.live);
    FundRefreshEvents.observeMessage(msg);
    if (msg.contentType == MessageType.custom &&
        msg.customElem?.description == 'assistantStream') {
      onRecvNewMessage?.call(msg);
      return;
    }
    initLogic.showNotification(msg);
    onRecvNewMessage?.call(msg);
  }

  void recvOfflineMessage(Message msg) {
    ChatHistoryCache.receivedMessage();
    AssistantStreamLog.received(msg,
        source: 'offline',
        hasReceiver:
            chatMessageEvents.hasListener || onRecvOfflineMessage != null);
    receivedMessages.addSafely(msg);
    publishChatMessage(msg, ChatMessageSource.offline);
    FundRefreshEvents.observeMessage(msg);
    if (msg.contentType == MessageType.custom &&
        msg.customElem?.description == 'assistantStream') {
      onRecvNewMessage?.call(msg);
      return;
    }
    // Offline deliveries update persisted state without replaying old alerts,
    // even when the native completion callback precedes the final deliveries.
    onRecvOfflineMessage?.call(msg);
  }

  void recvCustomBusinessMessage(String s) {
    customBusinessMessageSubject.addSafely(s);
  }

  void progressCallback(String msgId, int progress) {
    messageUploadProgress.addSafely(MsgStreamEv(id: msgId, value: progress));
    onMsgSendProgress?.call(msgId, progress);
  }

  void blacklistAdded(BlacklistInfo u) {
    blacklistChangedSubject.addSafely(u);
    onBlacklistAdd?.call(u);
  }

  void blacklistDeleted(BlacklistInfo u) {
    blacklistChangedSubject.addSafely(u);
    onBlacklistDeleted?.call(u);
  }

  void friendApplicationAccepted(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
  }

  void friendApplicationAdded(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
    friendApplicationAddedSubject.addSafely(u);
  }

  void friendApplicationDeleted(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
  }

  void friendApplicationRejected(FriendApplicationInfo u) {
    friendApplicationChangedSubject.addSafely(u);
  }

  void friendInfoChanged(FriendInfo u) {
    friendInfoChangedSubject.addSafely(u);
  }

  void friendAdded(FriendInfo u) {
    friendAddSubject.addSafely(u);
  }

  void friendDeleted(FriendInfo u) {
    friendDelSubject.addSafely(u);
  }

  void conversationChanged(List<ConversationInfo> list) {
    conversationChangedSubject.addSafely(list);
  }

  void newConversation(List<ConversationInfo> list) {
    conversationAddedSubject.addSafely(list);
  }

  void groupApplicationAccepted(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
  }

  void groupApplicationAdded(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
    groupApplicationAddedSubject.addSafely(info);
  }

  void groupApplicationDeleted(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
  }

  void groupApplicationRejected(GroupApplicationInfo info) {
    groupApplicationChangedSubject.add(info);
  }

  void groupInfoChanged(GroupInfo info) {
    groupInfoUpdatedSubject.addSafely(info);
  }

  void groupMemberAdded(GroupMembersInfo info) {
    memberAddedSubject.add(info);
  }

  void groupMemberDeleted(GroupMembersInfo info) {
    memberDeletedSubject.add(info);
  }

  void groupMemberInfoChanged(GroupMembersInfo info) {
    memberInfoChangedSubject.add(info);
  }

  void joinedGroupAdded(GroupInfo info) {
    joinedGroupAddedSubject.add(info);
  }

  void joinedGroupDeleted(GroupInfo info) {
    joinedGroupDeletedSubject.add(info);
  }

  void totalUnreadMsgCountChanged(int count) {
    initLogic.showBadge(count);
    unreadMsgCountEventSubject.addSafely(count);
  }

  void inputStateChanged(InputStatusChangedData status) {
    inputStateChangedSubject.addSafely(status);
  }

  void close() {
    resetNotificationReadiness();
    revokedMessages.close();
    deletedMessages.close();
    unreadMsgCountEventSubject.close();
    userStatusChangedSubject.close();
    customBusinessMessageSubject.close();
    inputStateChangedSubject.close();
    receivedMessages.close();
    chatMessageEvents.close();
    c2cReadReceipts.close();
    historyRecoverySignals.close();
    initializedSubject.close();
    friendApplicationChangedSubject.close();
    friendApplicationAddedSubject.close();
    groupApplicationAddedSubject.close();
    friendAddSubject.close();
    friendDelSubject.close();
    friendInfoChangedSubject.close();
    blacklistChangedSubject.close();
    selfInfoUpdatedSubject.close();
    groupInfoUpdatedSubject.close();
    conversationAddedSubject.close();
    conversationChangedSubject.close();
    conversationReadRequestSubject.close();
    conversationEntryReadSubject.close();
    memberAddedSubject.close();
    memberDeletedSubject.close();
    memberInfoChangedSubject.close();
    onKickedOfflineSubject.close();
    groupApplicationChangedSubject.close();
    imSdkStatusSubject.close();
    imSdkStatusPublishSubject.close();
    joinedGroupDeletedSubject.close();
    joinedGroupAddedSubject.close();
  }
}
