import 'messages/forwarding/pending_forward_store.dart';
import '../channels/models/channel_kind.dart';
import 'messages/forwarding/pending_forward.dart';
import 'package:openim_common/localization.dart';
import 'navigation/chat_entry_trace.dart';
import 'mentions/chat_mention_controller.dart';
import 'messages/quote/chat_quote_navigation.dart';
import 'media/chat_media_message_locator.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'messages/selection/message_selection_delete_sheet.dart';
import 'messages/widgets/message_action_confirmation_sheet.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:rxdart/rxdart.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../../routes/app_navigator.dart';
import '../../services/favorite_send_coordinator.dart';
import '../contacts/contacts_logic.dart';
import '../official_account/models/official_account.dart';
import '../official_account/presentation/official_account_timeline_policy.dart';
import '../ai_assistant/streaming/assistant_stream_chunk.dart';
import '../ai_assistant/streaming/assistant_stream_state.dart';
import '../ai_assistant/streaming/diagnostics/assistant_stream_log.dart';
import '../group_features/data/group_feature_runtime.dart';
import '../group_features/models/group_feature_context.dart';
import 'composer/chat_composer_controller.dart';
import 'calling/chat_call_controller.dart';
import 'appearance/chat_appearance_controller.dart';
import 'favorites/chat_favorites_controller.dart';
import 'fund/chat_fund_controller.dart';
import 'fund/confirmed_fund_cards.dart';
import 'fund/fund_card_recipient.dart';
import 'group_setup/group_member_list/group_member_list_logic.dart';
import 'group/chat_group_controller.dart';
import 'group/member_actions/chat_member_action_sheet.dart';
import 'group/member_actions/chat_member_actions_controller.dart';
import 'history/chat_timeline_controller.dart';
import 'history/chat_local_display_reader.dart';
import 'history/chat_history_prefetcher.dart';
import 'history/chat_history_diagnostics.dart';
import 'receipts/chat_read_diagnostics.dart';
import 'receipts/chat_persisted_latest_read.dart';
import 'history/chat_history_recovery.dart';
import 'history/chat_latest_message_recovery.dart';
import 'history/chat_background_message_recovery.dart';
import 'history/date_jump/chat_date_jump_controller.dart';
import 'history/date_jump/chat_date_window_controller.dart';
import 'history/date_jump/widgets/chat_date_picker_dialog.dart';
import 'media/chat_media_controller.dart';
import 'media/chat_media_preview_session.dart';
import 'media/upload/chat_media_outbox.dart';
import 'media/upload/chat_media_outbox_binding.dart';
import 'messages/chat_delivery_controller.dart';
import 'messages/chat_message_actions.dart';
import 'messages/revocation/chat_message_revocation.dart';
import 'messages/arrival/chat_message_arrival_controller.dart';
import 'messages/refresh/chat_message_read_updates.dart';
import 'messages/presentation/chat_message_presentation.dart';
import 'messages/presentation/chat_copy_text_cache.dart';
import 'messages/presentation/fund_notice_index.dart';
import 'messages/forwarding/chat_forwarding_controller.dart';
import 'messages/selection/message_selection_controller.dart';
import 'navigation/chat_message_navigation.dart';
import 'navigation/chat_message_focus_controller.dart';
import 'receipts/chat_read_receipts.dart';
import 'scrolling/chat_new_message_tracker.dart';
import 'scrolling/chat_latest_scroll_controller.dart';
import 'stickers/chat_sticker_controller.dart';
import 'stickers/builtin/chat_builtin_sticker.dart';
import 'stickers/personal_sticker_store.dart';
import 'voice/chat_voice_controller.dart';
import 'voice/voice_to_text_service.dart';
import 'voice/voice_transcription_controller.dart';

class ChatLogic extends SuperController {
  ChatLogic({DateTime Function()? receiptNow}) : _receiptNow = receiptNow;

  final DateTime Function()? _receiptNow;
  final messageReadUpdates = ChatMessageReadUpdates();
  final mediaPreviewSession = ChatMediaPreviewSession();
  late final fundNotices = FundNoticeIndex(messageList);
  bool _chatClosing = false;
  bool _messagesWhileCovered = false;
  int _coveredHistoryRevision = 0;
  bool _routeWasCurrent = true;
  bool _awaitingInitialHistorySync = false;
  Worker? _historyRecoveryWorker;
  String? _chatToken;
  String? _imToken;
  String? _chatRouteName;
  bool get _sameAccount =>
      _chatAccountID == OpenIM.iMManager.userID &&
      _chatToken == DataSp.chatToken &&
      _imToken == DataSp.imToken;
  bool get _sessionInactive => _chatClosing || isClosed || !_sameAccount;
  late final _historyRecovery = ChatHistoryRecovery(
    diagnostic: (event) =>
        ChatHistoryDiagnostics.record(conversationInfo.conversationID, event),
    isActive: () => _historyVisible,
    hasError: () => historyError.value != null,
    isLoading: () => historyLoading.value,
    windowRevision: () => historyWindowRevision.value,
    retry: () => _runHistoryRecovery(retry: true),
  );
  late final _latestMessageRecovery = ChatLatestMessageRecovery(
    diagnostic: (event) =>
        ChatHistoryDiagnostics.record(conversationInfo.conversationID, event),
    isClosed: () => _sessionInactive,
    latestMessage: () => conversationInfo.latestMsg,
    containsMessage: _timeline.containsMessage,
    isRemoved: _removedMessageIDs.contains,
    refresh: _loadHistoryForSyncEnd,
    canRefresh: () =>
        _historyVisible && !_dateWindow.buffering && historyError.value == null,
  );
  final assistantStreams = AssistantStreamState();
  late final _backgroundMessageRecovery = ChatBackgroundMessageRecovery(
    canRead: () =>
        _historyVisible &&
        !_dateWindow.seeking.value &&
        !_dateWindow.returning.value &&
        historyError.value == null,
    refreshLatest: () async {
      await _timeline.refresh();
      return !_sessionInactive && historyError.value == null;
    },
    onError: (error) => debugPrint('Chat background message recovery: $error'),
  );
  late final messageArrivals =
      ChatMessageArrivalController(currentUserID: () => _chatAccountID);
  late final ChatNewMessageTracker newMessages = ChatNewMessageTracker(
    currentUserID: () => OpenIM.iMManager.userID,
    isClosed: () => _sessionInactive,
    viewportDimension: () => scrollController.hasClients
        ? scrollController.position.viewportDimension
        : 0,
    hasMissingNewer: () => _dateWindow.buffering,
  );
  late final _latestScroll = ChatLatestScrollController(
    controller: scrollController,
    isClosed: () => _sessionInactive,
    shouldFollow: () => !newMessages.awayFromLatest.value,
    onReachedLatest: () => newMessages.updateScrollOffset(0),
  );
  late final _composer = ChatComposerController(
    conversationID: () => conversationInfo.conversationID,
    currentUserID: () => OpenIM.iMManager.userID,
    isGroupChat: () => isGroupChat,
    groupInfo: () => groupInfo,
    sendingMuted: () => sendingMuted,
    isSessionInactive: () => _sessionInactive || isOfficialNotificationChat,
    sendMessage: (message) async {
      await _sendMessage(message);
    },
    persistDraft: (id, draft) async {
      if (!_sameAccount || isOfficialNotificationChat) return;
      await OpenIM.iMManager.conversationManager
          .setConversationDraft(conversationID: id, draftText: draft);
    },
    selectMembers: (group, operation) async {
      final result = await AppNavigator.startGroupMemberList(
          groupInfo: group,
          opType: operation == ComposerMemberSelection.mention
              ? GroupMemberOpType.at
              : GroupMemberOpType.call);
      return result is List<GroupMembersInfo> ? result : null;
    },
    closeToolbox: closeToolbox,
    scrollBottom: () => scrollBottom(smooth: true),
    onTypingChanged: (focus) => sendTypingMsg(focus: focus),
    showError: IMViews.showToast,
  );
  late final _delivery = ChatDeliveryController(
    canSendToGroup: (id) => id != groupID || (!sendingMuted && !isInvalidGroup),
    groupSendBlockedMessage: () => isInvalidGroup
        ? StrRes.notSendMessageNotInGroup
        : (groupMembershipPending ? StrRes.synchronizing : StrRes.youMuted),
    uploadProgress: imLogic.messageUploadProgress,
    accountID: _chatAccountID,
    messageList: messageList,
    conversation: () => conversationInfo,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    groupStatus: () => groupInfo?.status,
    scrollBottom: scrollBottom,
    resetInput: (message) => _composer.resetAfterSend(message),
    onTimelineChanged: _trimAutomaticWindow,
    onMessageChanged: messageReadUpdates.notify,
    onDeliveryStarted: (message, target) => !_sessionInactive &&
            isSingleChat &&
            userID == 'assistant' &&
            target.userID == 'assistant'
        ? assistantStreams.beginReply()
        : null,
    onDeliveryFinished: (waiting, message) {
      if (_sessionInactive || message.status != MessageStatus.succeeded) {
        assistantStreams.cancelReply(waiting as int?);
      }
    },
  );
  late final _readDiagnostics =
      ChatReadDiagnostics(conversationInfo.conversationID);
  bool get _historyBlocksRead =>
      !_timeline.hasPublishableWindow &&
      historyLoading.value &&
      !canReadPersistedLatestDuringLoad(
          conversationInfo, messageList.lastOrNull);
  Map<String, Object?> _readDiagnosticState() => {
        'routeCurrent': _messageRoute?.isCurrent,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'sameAccount': _sameAccount,
        'getxClosed': isClosed,
        'chatClosing': _chatClosing,
        'syncStatus': syncStatus.value.name,
        'historyLoading': historyLoading.value,
        'historyBlocksRead': _historyBlocksRead,
        'historyError': historyError.value != null,
        'viewingHistory': viewingHistory.value,
        'entering': messageArrivals.hasEntering,
        'messagesWhileCovered': _messagesWhileCovered,
        'blockedReasons': [
          if (_messagesWhileCovered) 'messages_while_covered',
          if (messageArrivals.hasEntering) 'entry_animation',
          if (_historyBlocksRead) 'history_loading',
          if (historyError.value != null) 'history_error',
          if (viewingHistory.value) 'history_window',
          if (syncStatus.value == IMSdkStatus.syncStart ||
              syncStatus.value == IMSdkStatus.syncProgress ||
              syncStatus.value == IMSdkStatus.synchronizing)
            'sync_in_progress',
        ],
      };
  late final _receipts = ChatReadReceipts(
    diagnostics: _readDiagnostics,
    diagnosticState: _readDiagnosticState,
    now: _receiptNow,
    messageList: messageList,
    conversation: () => conversationInfo,
    // GetX marks isClosed before onClose. Keep this owner alive until the
    // synchronous final painted read has been sent, then close it below.
    isClosed: () => _chatClosing || !_sameAccount,
    canReadConversation: () =>
        !_messagesWhileCovered &&
        !messageArrivals.hasEntering &&
        !_historyBlocksRead &&
        historyError.value == null &&
        !viewingHistory.value &&
        (_timeline.hasPublishableWindow ||
            (syncStatus.value != IMSdkStatus.syncStart &&
                syncStatus.value != IMSdkStatus.syncProgress &&
                // A global sync failure can concern another conversation. A healthy
                // local history and its painted latest still permit an SDK read; the
                // receipt owner separately rejects a missing/unseen preview target.
                syncStatus.value != IMSdkStatus.synchronizing)),
    isActive: () =>
        (_messageRoute?.isCurrent ?? Get.currentRoute == _chatRouteName) &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed),
    isSessionActive: () => _sameAccount,
    onConversationRead: (request) =>
        imLogic.conversationReadRequestSubject.addSafely(request),
    onReadStateChanged: (ids) {
      if (!_sessionInactive) messageReadUpdates.notify(ids);
    },
  );
  late final ChatVoiceController _voice = ChatVoiceController(
    conversationID: conversationInfo.conversationID,
    messages: () => messageList,
    bufferedMessages: () => scrollingCacheMessageList,
    isMessageRemoved: _removedMessageIDs.contains,
    markMessageRead: _receipts.markRead,
    sendMessage: (message, {resetInput = true}) async {
      await _sendMessage(message, resetInput: resetInput);
    },
    canSend: () => !_sessionInactive && !sendingMuted && !isInvalidGroup,
    attachmentBusy: () => _media.pickingAttachment,
  );
  late final ChatMediaController _media = ChatMediaController(
    acceptSendTask: () => ChatMediaOutbox.instance.accept(FavoriteTarget(
        conversationID: conversationInfo.conversationID,
        userID: userID,
        groupID: groupID,
        sessionType: conversationInfo.conversationType)),
    onTransfer: (message, state) =>
        _delivery.updateTransfer(message.clientMsgID, state),
    onUploadFailed: (message) {
      if (!_sessionInactive) _delivery.messageChanged(message);
    },
    conversationID: () => conversationInfo.conversationID,
    isClosed: () => _sessionInactive,
    sendingMuted: () => sendingMuted,
    isInvalidGroup: () => isInvalidGroup,
    voiceBusy: () => _voice.busy,
    sendMessage: (message, {addToUI = true, resetInput = true}) =>
        _sendMessage(message, addToUI: addToUI, resetInput: resetInput),
    stageMessage: (message) {
      if (_sessionInactive) return;
      messageList.add(message);
      _trimAutomaticWindow();
      scrollBottom();
    },
    previewVoice: _voice.previewAndSendVoice,
    closeToolbox: closeToolbox,
  );
  late final _stickers = ChatStickerController(
    isClosed: () => _sessionInactive,
    sendingMuted: () => sendingMuted,
    isInvalidGroup: () => isInvalidGroup,
    sendMessage: _sendMessage,
    sendBuiltinMessage: (message) => _sendMessage(message, resetInput: false),
    closeToolbox: closeToolbox,
  );
  late final _funds = ChatFundController(
    messages: messageList,
    onPaidCardReady: () => scrollBottom(),
    isClosed: () => _sessionInactive,
    canSend: () => !sendingMuted && !isInvalidGroup,
    userID: () => isSingleChat ? userID : null,
    groupID: () => isGroupChat ? groupID : null,
    recipientName: () => isSingleChat ? nickname.value : null,
    recipientFaceURL: () => isSingleChat ? faceUrl.value : null,
    closeToolbox: () {
      closeToolbox();
      // Clear this route's focus history before pushing a fund page so
      // popping it cannot automatically reopen the chat keyboard.
      focusNode.enclosingScope?.unfocus();
      focusNode.unfocus();
    },
  );
  late final _favorites = ChatFavoritesController(
    messageList: messageList,
    delivery: _delivery,
    conversation: () => conversationInfo,
    accountID: _chatAccountID,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    sendingMuted: () => sendingMuted,
    isInvalidGroup: () => isInvalidGroup,
    displayName: () => nickname.value,
    unfocus: () => focusNode.unfocus(),
  );
  late final _actions = ChatMessageActions(
    conversationID: () => conversationInfo.conversationID,
    removeMessage: _removeMessageByID,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
  );
  late final _revocation = ChatMessageRevocation(
    confirm: (message) async {
      final context = Get.context;
      if (_sessionInactive || context == null || !context.mounted) return false;
      return MessageActionConfirmationSheet.show(
        context,
        title: message.isGroupChat && message.sendID != OpenIM.iMManager.userID
            ? 'chatMessageRevokeMemberConfirm'.trParams({
                'name': getNewestNickname(message)?.trim().isNotEmpty == true
                    ? getNewestNickname(message)!.trim()
                    : message.senderNickname?.trim().isNotEmpty == true
                        ? message.senderNickname!.trim()
                        : message.sendID ?? '',
              })
            : 'chatMessageRevokeConfirm'.tr,
        action: StrRes.menuRevoke,
        sheetKey: const ValueKey('message-revoke-confirmation-sheet'),
      );
    },
    conversationID: () => conversationInfo.conversationID,
    currentUserID: () => OpenIM.iMManager.userID,
    groupID: () => groupID,
    groupInfo: () => groupInfo,
    memberRole: _group.memberRoleFor,
    isJoined: () => isInGroup.value,
    groupRevision: () => _group.memberActionRevision,
    isCurrentMessage: (message) =>
        isCurrentChat(message) &&
        !_removedMessageIDs.contains(message.clientMsgID),
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    onRevoked: (id) => _revokeMessageNotice(RevokedInfo(
      clientMsgID: id,
      revokerID: OpenIM.iMManager.userID,
      revokerNickname: senderName,
    )),
    showFeedback: IMViews.showToast,
  );
  late final PendingForwardController pendingForward;
  PendingForward? _incomingForward;
  late final ChatForwardingController _forwarding = ChatForwardingController(
    delivery: _delivery,
    messages: () => messageList,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    isGroupChat: () => isGroupChat,
    nickname: () => nickname.value,
    faceUrl: () => faceUrl.value,
    canForward: canForward,
    closeToolbox: closeToolbox,
    onForwardNeedsReview: () {
      messageSelection.cancel();
      pendingForward.draft.value = null;
    },
    stageForward: (messages, recipient, merged) => AppNavigator.stageForward(
      PendingForward(messages, recipient,
          merged: merged,
          mergeTitle: '${nickname.value} · ${'sdkMergedHistory'.tr}'),
      isCurrent: () => !_sessionInactive,
    ),
  );
  late final MessageSelectionController messageSelection =
      MessageSelectionController(
    messages: () => messageList,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    onStart: () {
      messageArrivals.cancel();
      closeToolbox();
      focusNode.unfocus();
      _latestScroll.cancel();
    },
    deleteMessages: _actions.deleteMessages,
    forwardMessages: _forwarding.forwardMessages,
  );
  Worker? _messageSelectionWorker;
  late final _navigation = ChatMessageNavigation(
    isClosed: () => _sessionInactive,
    isGroupChat: () => isGroupChat,
    isSingleChat: () => isSingleChat,
    isAdminOrOwner: () => isAdminOrOwner,
    groupID: () => groupID,
    groupInfo: () => groupInfo,
  );
  TextEditingController get inputCtrl => _composer.inputCtrl;
  FocusNode get focusNode => _composer.focusNode;
  Rxn<Message> get quotedMessage => _composer.quotedMessage;
  RxList<GroupMembersInfo> get directionalUsers => _composer.directionalUsers;
  VoicePlaybackController get voicePlayback => _voice.playback;
  VoiceTranscriptionController get voiceTranscriptions => _voice.transcriptions;
  VoiceToTextService get voiceToTextService => _voice.service;
  PersonalStickerStore get personalStickers => _stickers.personalStickers;
  PublishSubject<MsgStreamEv<bool>> get sendStatusSub =>
      _delivery.sendStatusSub;
  ValueListenable<ChatTransferStatus?>? transferStatus(Message message) =>
      _delivery.transferFor(message);
  void checkDelivery(Message message) => _delivery.checkDelivery(message);

  late final _calling = ChatCallController(
    im: imLogic,
    userID: () => userID,
    nickname: () => nickname.value,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    isSingleChat: () => isSingleChat,
    busy: () => PackageBridge.rtcBridge?.hasConnection == true,
  );
  late final _appearance = ChatAppearanceController(
    otherID: () => otherId,
    isClosed: () => _sessionInactive,
  );
  RxDouble get scaleFactor => _appearance.scaleFactor;
  RxString get background => _appearance.background;
  bool get rtcIsBusy => _calling.rtcIsBusy;

  late final _group = ChatGroupController(
    im: imLogic,
    groupID: () => groupID,
    messages: messageList,
    clearInput: () => inputCtrl.clear(),
    readCachedGroupInfo: (id) => groupFeatures.cachedGroupInfo(id),
    onGroupInfoApplied: (info) {
      if (!_sessionInactive) groupFeatures.seed(info);
    },
    onGroupProfileChanged: (name, face) {
      if (_sessionInactive) return;
      if (name.trim().isNotEmpty) nickname.value = name;
      faceUrl.value = face;
    },
  );
  GroupInfo? get groupInfo => _group.groupInfo;
  late final GroupFeatureStore groupFeatures =
      GroupFeatureRuntime.forAccount(imLogic);
  GroupFeatureContext get groupFeatureContext => groupFeatures.context(
      id: groupID ?? '',
      name: nickname.value,
      userID: _chatAccountID,
      admin: isAdminOrOwner,
      current: () => !_sessionInactive && !isInvalidGroup);
  GroupMembersInfo? get groupMembersInfo => _group.groupMembersInfo;
  List<GroupMembersInfo> get ownerAndAdmin => _group.ownerAndAdmin;
  Map<String, GroupMembersInfo> get memberUpdateInfoMap =>
      _group.memberUpdateInfoMap;
  RxInt get groupMemberRoleLevel => _group.groupMemberRoleLevel;
  RxBool get isInGroup => _group.isInGroup;
  RxInt get memberCount => _group.memberCount;
  RxString get announcement => _group.announcement;
  RxString get announcementVersion => _group.announcementVersion;
  String? get groupOwnerID => _group.groupOwnerID;
  bool get sendingMuted => isOfficialNotificationChat || _group.sendingMuted;
  bool get personallyMuted => _group.personallyMuted;
  bool get isChannel => _group.isChannel;
  bool get isChannelSubscriber => isChannel && !_group.isAdminOrOwner;
  bool get groupMutePending =>
      !isOfficialNotificationChat && _group.muteStatusPending;
  bool get groupMembershipPending => _group.membershipPending.value;

  late final _memberActions = ChatMemberActionsController(
    groupID: () => groupID,
    currentUserID: () => OpenIM.iMManager.userID,
    isSessionInactive: () => _sessionInactive,
    isJoined: () => isInGroup.value,
    groupRevision: () => _group.memberActionRevision,
    sendingMuted: () => sendingMuted,
    latestMember: (id) => memberUpdateInfoMap[id],
    latestGroup: () => groupInfo,
    isKnownRemoved: _group.hasMemberLeft,
    mention: mentionMessageSender,
    sendExclusiveRedPacket: _funds.sendExclusiveRedPacket,
    memberUpdated: imLogic.memberInfoChangedSubject.addSafely,
    memberRemoved: imLogic.memberDeletedSubject.addSafely,
    showFeedback: IMViews.showToast,
    runLoading: <T>(action) =>
        LoadingView.singleton.wrap<T>(asyncFunction: action),
  );

  final imLogic = Get.find<IMController>();

  final scrollController = ScrollController(keepScrollOffset: false);
  final messagePositionController = ChatListPositionController();
  final refreshController = RefreshController();
  bool playOnce = false;
  final peerTyping = false.obs;
  final _messageSubscriptions = <StreamSubscription>[];
  Timer? _typingExpiry;

  Set<String> get _removedMessageIDs => _timeline.removedIDs;
  void _removeMessageByID(String? id) {
    if (id == null || _sessionInactive) return;
    newMessages.remove(id);
    if (isGroupChat) mentions.remove(id);
    _timeline.remove(id);
    if (messageList.isEmpty && scrollingCacheMessageList.isEmpty) {
      newMessages.reset();
    }
    _voice.removeMessage(id);
    copyTextMap.remove(id);
    if (quotedMessage.value?.clientMsgID == id) clearReply();
  }

  void _revokeMessageNotice(RevokedInfo info) {
    final id = info.clientMsgID;
    if (id == null || _sessionInactive) return;
    newMessages.remove(id);
    if (isGroupChat) mentions.remove(id);
    _timeline.revoke(info);
    _voice.removeMessage(id);
    copyTextMap.remove(id);
    if (quotedMessage.value?.clientMsgID == id) clearReply();
  }

  final forceCloseToolbox = PublishSubject<bool>();

  late ConversationInfo conversationInfo;
  ChatEntryTrace? entryTrace;
  Worker? _entryReadyWorker;
  OfficialAccount? _officialAccount;
  OfficialAccount? get officialAccount => isSingleChat
      ? _officialAccount ??
          OfficialAccount.from(userID: userID, ex: conversationInfo.ex)
      : null;
  bool get isOfficialNotificationChat => officialAccount != null;
  Message? searchMessage;
  final nickname = ''.obs;
  final faceUrl = ''.obs;
  String _chatAccountID = '';
  Function(Message)? _ownedMessageCallback;
  Function(List<ReadReceiptInfo>)? _ownedReceiptCallback;
  Function(SignalingMessageEvent)? _ownedSignalingCallback;
  late final ChatTimelineController _timeline = ChatTimelineController(
    beforeLatestReplace: () => _dateWindow.prepareLatestTransition(),
    onLatestDeferred: () => newMessages.updateScrollOffset(0),
    fetchLocalSnapshot: () => OpenIM.iMManager.messageManager
        .getLocalHistorySnapshot(
            conversationID: conversationInfo.conversationID),
    fetchDisplaySnapshot: () => readChatLocalDisplay(conversationInfo),
    fetchWindow: () =>
        OpenIM.iMManager.messageManager.peekLocalMessageWindow(
            conversationID: conversationInfo.conversationID) ??
        OpenIM.iMManager.messageManager.getLocalMessageWindow(
            conversationID: conversationInfo.conversationID),
    canPaintInitialWindow: () => ![
      IMSdkStatus.syncStart,
      IMSdkStatus.synchronizing,
      IMSdkStatus.syncProgress,
    ].contains(imLogic.currentSdkStatus),
    accountID: _chatAccountID,
    isSessionCurrent: () => _sameAccount,
    conversation: () => conversationInfo,
    timelineTimeMarker: isOfficialNotificationChat
        ? OfficialAccountTimelinePolicy.markTimes
        : null,
    fetch: ({required count, startMsg}) => startMsg == null
        ? ChatHistoryPrefetcher.shared
            .readLatest(conversationInfo, count: count)
        : OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
            conversationID: conversationInfo.conversationID,
            count: count,
            startMsg: startMsg),
    fetchNewer: ({required count, startMsg}) => OpenIM.iMManager.messageManager
        .getAdvancedHistoryMessageListReverse(
            conversationID: conversationInfo.conversationID,
            count: count,
            startMsg: startMsg),
    isClosed: () => _sessionInactive,
    onFirstPage: () {
      if (!_dateWindow.buffering) {
        if (_latestScroll.followingEntry) {
          messagePositionController.requestLatestLayout();
        }
        _latestScroll.requestEntry(complete: true);
      }
      if (!_dateWindow.buffering && !newMessages.awayFromLatest.value) {
        scrollBottom(force: false);
      }
    },
    captureOffset: () =>
        scrollController.hasClients ? scrollController.offset : 0.0,
    restoreOffset: (offset) {
      final followLatest = !newMessages.awayFromLatest.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_sessionInactive && scrollController.hasClients) {
          final position = scrollController.position;
          scrollController.jumpTo(followLatest
              ? position.minScrollExtent
              : offset.clamp(
                  position.minScrollExtent, position.maxScrollExtent));
        }
      });
    },
    onFirstLoaded: _getGroupInfoAfterLoadMessage,
    preserveReading: () =>
        !_latestScroll.followingEntry && newMessages.awayFromLatest.value,
    canTrimHistory: (older) {
      if (_sessionInactive ||
          messageSelection.active ||
          _dateWindow.buffering ||
          _messageRoute?.isCurrent != true ||
          !scrollController.hasClients) {
        return false;
      }
      final position = scrollController.position;
      if (!position.hasContentDimensions) return false;
      // Check again after the SDK page arrives: the reader may have moved.
      final distance = older ? position.extentAfter : position.extentBefore;
      return distance <= position.viewportDimension;
    },
  );
  RxList<Message> get messageList => _timeline.messageList;
  List<Message> get scrollingCacheMessageList =>
      _timeline.scrollingCacheMessageList;
  RxBool get initialHistoryLoading => _timeline.initialHistoryLoading;
  RxBool get initialWindowReady => _timeline.initialWindowReady;
  RxBool get historyLoading => _timeline.historyLoading;
  RxBool get historyPagingLoading => _timeline.historyPagingLoading;
  RxnString get historyError => _timeline.historyError;
  RxBool get historyHasMore => _timeline.historyHasMore;
  RxBool get historyScanLimited => _timeline.historyScanLimited;
  RxBool get viewingHistory => _timeline.viewingHistory;
  RxBool get historyNewerHasMore => _timeline.newerHasMore;
  bool get bufferingLiveMessages => _dateWindow.buffering;

  late final _dateWindow = ChatDateWindowController(
    timeline: _timeline,
    positions: messagePositionController,
    isClosed: () => _sessionInactive,
    cancelLatestScroll: _latestScroll.cancel,
    updateScrollOffset: newMessages.updateScrollOffset,
    distanceFromLatest: () => scrollController.hasClients
        ? scrollController.offset - scrollController.position.minScrollExtent
        : 0,
    requestLatestScroll: (smooth) =>
        _latestScroll.request(force: true, animated: smooth),
  );

  Future<bool> jumpToDateMessage(Message message) =>
      _dateWindow.jumpToMessage(message);

  Route<dynamic>? _messageRoute;
  bool get isMessageNavigationCurrent => !_sessionInactive;
  Route<dynamic>? get messageRoute => _messageRoute;
  void bindMessageRoute(Route<dynamic>? route) {
    if (_sessionInactive) return;
    _messageRoute = route;
    final current = route?.isCurrent != false;
    if (!current && _routeWasCurrent && newMessages.awayFromLatest.value) {
      _backgroundMessageRecovery.suspend();
    }
    if (current && !_routeWasCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_sessionInactive && route?.isCurrent == true) {
          if (_messagesWhileCovered ||
              historyError.value != null ||
              _backgroundMessageRecovery.hasCheckpoint) {
            unawaited(_loadHistoryForSyncEnd());
          }
          _historyRecovery.request(
              resetAttempts: true, source: 'route_visible');
          _latestMessageRecovery.conversationChanged(resetAttempts: true);
        }
      });
    }
    _routeWasCurrent = current;
  }

  late final _messageFocus = ChatMessageFocusController(
    canFocus: (message) =>
        !_sessionInactive &&
        isCurrentChat(message) &&
        message.clientMsgID?.isNotEmpty == true &&
        !_removedMessageIDs.contains(message.clientMsgID),
    jump: jumpToDateMessage,
  );
  RxnString get focusedMessageID => _messageFocus.highlightedID;
  late final mentions = ChatMentionController(
    userID: () => _chatAccountID,
    isClosed: () => _sessionInactive,
    search: (page) async {
      final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
        conversationID: conversationInfo.conversationID,
        messageTypeList: [MessageType.atText],
        pageIndex: page,
        count: 50,
      );
      return [
        for (final item in result.searchResultItems ?? <SearchResultItems>[])
          if (item.conversationID == conversationInfo.conversationID)
            ...?item.messageList,
      ];
    },
    focus: focusSearchMessage,
  );

  Future<void> jumpToMention() async {
    try {
      if (!await mentions.jump() && !_sessionInactive) {
        IMViews.showToast(AppCopy.text('暂时无法定位该消息，请重试'));
      }
    } catch (_) {
      if (!_sessionInactive) IMViews.showToast(AppCopy.text('暂时无法定位该消息，请重试'));
    }
  }

  RxInt get historyWindowRevision => _timeline.windowRevision;

  Future<bool> focusSearchMessage(Message message) {
    if (_sessionInactive || !isCurrentChat(message) || message.hasExpired) {
      return Future.value(false);
    }
    messageSelection.cancel();
    closeToolbox();
    focusNode.unfocus();
    return _messageFocus.focus(message);
  }

  late final _quoteNavigation = ChatQuoteNavigation(
    findMessage: (id) => ChatMediaMessageLocator.findStoredMessage(
        conversationID: conversationInfo.conversationID, clientMsgID: id),
    focusMessage: focusSearchMessage,
    isAvailable: (message) =>
        isCurrentChat(message) &&
        !_removedMessageIDs.contains(message.clientMsgID) &&
        message.contentType != MessageType.revokeMessageNotification,
    showFeedback: IMViews.showToast,
  );

  Future<bool> openQuotedMessage(BuildContext context, Message message) {
    final route = ModalRoute.of(context);
    return _quoteNavigation.open(message,
        isCurrent: () =>
            context.mounted && !_sessionInactive && route?.isCurrent == true);
  }

  late final _dateJump = ChatDateJumpController(
    conversationID: () => conversationInfo.conversationID,
    isClosed: () => _sessionInactive,
    isRemoved: (message) => _removedMessageIDs.contains(message.clientMsgID),
    messages: () => messageList,
    search: (
            {required conversationID,
            required messageTypeList,
            required searchTimePosition,
            required searchTimePeriod,
            required pageIndex,
            required count}) =>
        OpenIM.iMManager.messageManager.searchLocalMessages(
            conversationID: conversationID,
            messageTypeList: messageTypeList,
            searchTimePosition: searchTimePosition,
            searchTimePeriod: searchTimePeriod,
            pageIndex: pageIndex,
            count: count),
    jumpToMessage: (id, message, day) async {
      if (!await jumpToDateMessage(message) && !_sessionInactive) {
        throw StateError('The date message could not be positioned');
      }
    },
    showFeedback: IMViews.showToast,
    runLoading: (action) => LoadingView.singleton.wrap(asyncFunction: action),
  );

  Future<void> onTapTimeline(BuildContext context, Message message) async {
    final time = message.sendTime;
    if (_sessionInactive || time == null || messageSelection.active) return;
    closeToolbox();
    focusNode.unfocus();
    await _dateJump.pickAndJump(
      initialDate: DateTime.fromMillisecondsSinceEpoch(time),
      pickDate: (date) => showChatDatePicker(
        context: context,
        conversationID: conversationInfo.conversationID,
        initialDate: date,
        isCurrent: () => !_sessionInactive,
        knownDayHasMessages: _dateJump.hasLoadedMessagesOn,
        isRemoved: (message) =>
            _removedMessageIDs.contains(message.clientMsgID),
      ),
    );
  }

  final isInBlacklist = false.obs;

  late StreamSubscription conversationSub;
  late StreamSubscription friendInfoChangedSub;
  StreamSubscription? userStatusChangedSub;
  StreamSubscription? selfInfoUpdatedSub;

  late StreamSubscription connectionSub;
  final syncStatus = IMSdkStatus.syncEnded.obs;

  final Map<String?, String?> copyTextMap = ChatCopyTextCache();

  String? get userID => conversationInfo.userID;

  String? get groupID => conversationInfo.groupID;

  bool get isSingleChat => null != userID && userID!.trim().isNotEmpty;

  bool get isGroupChat => null != groupID && groupID!.trim().isNotEmpty;

  String get memberStr => isSingleChat || !_group.memberCountKnown.value
      ? ''
      : (isChannelEx(_group.groupInfo?.ex)
              ? 'channelSubscriberCountLabel'
              : 'groupMemberCountLabel')
          .trArgs(['$memberCount']);

  String? get senderName => isSingleChat
      ? OpenIM.iMManager.userInfo.nickname
      : groupMembersInfo?.nickname;

  bool get isAdminOrOwner => _group.isAdminOrOwner;

  bool isCurrentChat(Message message) {
    var senderId = message.sendID;
    var receiverId = message.recvID;
    var groupId = message.groupID;

    var isCurSingleChat = message.isSingleChat &&
        isSingleChat &&
        (senderId == userID &&
                (receiverId == null ||
                    receiverId.isEmpty ||
                    receiverId == _chatAccountID) ||
            senderId == _chatAccountID && receiverId == userID);
    var isCurGroupChat =
        message.isGroupChat && isGroupChat && groupID == groupId;
    return isCurSingleChat || isCurGroupChat;
  }

  void scrollBottom({bool force = true, bool smooth = false}) {
    if (_sessionInactive) return;
    if (force) {
      _dateJump.invalidate();
      unawaited(_dateWindow.returnToLatest(smooth: smooth));
    } else if (!_dateWindow.buffering) {
      _latestScroll.request(force: false, animated: smooth);
    }
  }

  bool get hasDeferredLatest => _timeline.latestDeferred.value;
  bool get latestWindowFading => _dateWindow.fading.value;

  bool onChatScrollNotification(ScrollNotification notification) {
    if (_sessionInactive) return false;
    if (notification.depth == 0 &&
        notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      messageArrivals.cancel();
      _latestScroll.endEntry();
      messagePositionController.cancel();
      _messageFocus.cancel();
      _dateWindow.invalidate();
      _dateJump.invalidate();
      focusNode.unfocus();
    }
    return false;
  }

  void _onChatScrolled() {
    if (_sessionInactive || !scrollController.hasClients) return;
    final distance =
        scrollController.offset - scrollController.position.minScrollExtent;
    // Lazy, variable-height rows can refine an estimated latest edge in layout.
    // Only the painted viewport (or an explicit return) confirms reaching it.
    newMessages.updateScrollOffset(distance, viewportConfirmed: false);
  }

  void _trimAutomaticWindow() {
    _automaticTrimPending =
        messageList.length > ChatTimelineController.automaticWindowLimit;
    if (!_automaticTrimPending) return;
    if (_sessionInactive ||
        messageSelection.active ||
        newMessages.awayFromLatest.value ||
        _dateWindow.buffering) {
      return;
    }
    _timeline.trimLatestWindow();
    // Extra sending/failed rows are intentional. Retry only on the next
    // message/status change, rather than rescanning them on every frame.
    _automaticTrimPending = false;
  }

  bool _automaticTrimPending = false;

  void onChatViewportChanged(List<String> readIDs, double distanceFromLatest) {
    if (_sessionInactive) return;
    _timeline.recordPaintedRows(readIDs);
    // A size transition is a clipped slice until its final layout. Only that
    // full-height painted frame may count as seeing the message or start burn.
    readIDs = readIDs.where((id) => !messageArrivals.isEntering(id)).toList();
    newMessages
        .updateScrollOffset(_dateWindow.buffering ? 2 : distanceFromLatest);
    if (_automaticTrimPending) _trimAutomaticWindow();
    for (final id in readIDs) {
      newMessages.markVisible(id);
    }
    unawaited(_receipts.markVisibleMessages(readIDs,
        atLatest: !_dateWindow.buffering));
  }

  bool _isAssistantReply(Message message) =>
      isSingleChat &&
      userID == 'assistant' &&
      message.isSingleChat &&
      message.sendID == 'assistant' &&
      message.recvID == _chatAccountID;

  void _reconcileAssistantReplies() {
    if (_sessionInactive || userID != 'assistant') return;
    for (final message in messageList) {
      if (_isAssistantReply(message)) {
        assistantStreams.markFinalMessage(message);
      }
    }
  }

  void _appendLiveMessage(Message message, {bool recovered = false}) {
    // Online deltas have no history, read receipt, unread count or message menu.
    if (AssistantStreamChunk.isStreamMessage(message)) {
      if (!_sessionInactive && _isAssistantReply(message)) {
        final chunk = AssistantStreamChunk.tryParse(message);
        if (chunk != null) {
          _typingExpiry?.cancel();
          peerTyping.value = false;
          final snapshot = assistantStreams.accept(chunk);
          AssistantStreamLog.accepted(chunk, snapshot,
              buffering: bufferingLiveMessages,
              finalized: assistantStreams.isFinalized(chunk.streamID));
          if (snapshot != null) {
            scrollBottom(force: false);
          }
        } else {
          AssistantStreamLog.invalid(message);
        }
      }
      return;
    }
    if (!_sessionInactive && _isAssistantReply(message)) {
      AssistantStreamLog.finalReply(message);
      if (!_timeline.containsMessage(message.clientMsgID) &&
          !_removedMessageIDs.contains(message.clientMsgID)) {
        assistantStreams.receivedReply(message);
      } else {
        assistantStreams.markFinalMessage(message);
      }
    }
    if (!_sessionInactive && isSingleChat && message.sendID == userID) {
      if (message.contentType == MessageType.typing) {
        _typingExpiry?.cancel();
        peerTyping.value = message.typingElem?.msgTips == 'yes';
        if (peerTyping.value) {
          _typingExpiry = Timer(
              const Duration(seconds: 65), () => peerTyping.value = false);
        }
        return;
      }
      // A complete SDK reply ends the transient typing state immediately.
      _typingExpiry?.cancel();
      peerTyping.value = false;
    }
    if (_sessionInactive ||
        message.contentType == MessageType.typing ||
        _removedMessageIDs.contains(message.clientMsgID) ||
        _timeline.containsMessage(message.clientMsgID)) {
      return;
    }
    if (scrollController.hasClients) {
      final distance =
          scrollController.offset - scrollController.position.minScrollExtent;
      newMessages.updateScrollOffset(distance, viewportConfirmed: false);
    }
    if (isGroupChat) mentions.add(message);
    final followLatest = !newMessages.awayFromLatest.value;
    if (_dateWindow.buffering ||
        _timeline.holdForIncoming(awayFromLatest: !followLatest)) {
      newMessages.updateScrollOffset(2);
      newMessages.recordIncoming(message);
      _timeline.bufferIncoming(message);
      return;
    }
    messageArrivals.register(message,
        enabled: !recovered &&
            followLatest &&
            !_historyBlocksRead &&
            syncStatus.value == IMSdkStatus.syncEnded &&
            _timeline.hasLoadedHistory &&
            !isOfficialNotificationChat &&
            !messageSelection.active &&
            _messageRoute?.isCurrent == true &&
            (messageList.isEmpty ||
                (scrollController.hasClients &&
                    !scrollController.position.isScrollingNotifier.value)) &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed) &&
            !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
                .disableAnimations);
    newMessages.recordIncoming(message);
    final trim =
        followLatest && !messageSelection.active && !_dateWindow.buffering;
    _timeline.appendIncoming(message, trim: trim);
    _automaticTrimPending = !trim &&
        messageList.length > ChatTimelineController.automaticWindowLimit;
    if (followLatest) {
      scrollBottom(force: false);
    }
  }

  Future<List<Message>> searchMediaMessage(
          {bool Function()? continueLoading}) =>
      _media.searchMediaMessage(continueLoading: continueLoading);

  @override
  void onReady() {
    if (_sessionInactive) return;
    // Another mounted route can observe this conversation-owned draft. GetX
    // calls onReady after the frame, when notifying that route is safe.
    final incomingForward = _incomingForward;
    _incomingForward = null;
    if (incomingForward != null && !pendingForward.sending.value) {
      pendingForward.draft.value = incomingForward;
    }
    _resetGroupAtType();
    _clearUnreadCount();

    final target = searchMessage;
    searchMessage = null;
    if (target != null) unawaited(focusSearchMessage(target));

    super.onReady();
  }

  @override
  void onInit() {
    var arguments = Get.arguments;
    entryTrace = arguments['chatEntryTrace'] as ChatEntryTrace?;
    entryTrace?.mark('init_start');
    conversationInfo = arguments['conversationInfo'];
    pendingForward = PendingForwardStore.shared.conversation(
      accountID: OpenIM.iMManager.userID,
      sessionToken: DataSp.imToken,
      conversationID: conversationInfo.conversationID,
    );
    _incomingForward = arguments['pendingForward'] as PendingForward?;
    _readDiagnostics
        .record('route_enter', {'unreadCount': conversationInfo.unreadCount});
    final account = arguments['officialAccount'];
    if (account is OfficialAccount &&
        account.userID == conversationInfo.userID) {
      _officialAccount = account;
    }
    _chatRouteName = Get.currentRoute;
    _chatAccountID = OpenIM.iMManager.userID;
    _chatToken = DataSp.chatToken;
    _imToken = DataSp.imToken;
    if (isGroupChat) {
      final latestSeq = conversationInfo.latestMsg?.seq ?? 0;
      unawaited(mentions
          .load(
        unreadCount: conversationInfo.unreadCount,
        latestSeq: latestSeq,
        hasMention: conversationInfo.groupAtType != null &&
            conversationInfo.groupAtType != GroupAtType.atNormal,
      )
          .catchError((Object error) {
        if (!_sessionInactive) debugPrint('Mention lookup failed: $error');
      }));
    }
    _entryReadyWorker = ever(initialWindowReady, (bool ready) {
      if (ready && !_sessionInactive) {
        entryTrace?.mark('window_ready');
        if (_latestScroll.followingEntry) {
          messagePositionController.requestLatestLayout();
        }
        _latestScroll.requestEntry();
      }
    });
    if (searchMessage != null) _latestScroll.endEntry();
    _timeline.initialize(prefetch: false);
    _messageSubscriptions.add(bindMediaOutbox(
        conversationID: conversationInfo.conversationID,
        messages: messageList,
        isClosed: () => _sessionInactive,
        removedIDs: _removedMessageIDs,
        onAdded: () {
          _trimAutomaticWindow();
          scrollBottom();
        },
        delivery: _delivery));
    _reconcileAssistantReplies();
    _messageSelectionWorker = ever(messageList, (_) {
      messageSelection.sync();
      _reconcileAssistantReplies();
    });
    _composer.initialize(
        isOfficialNotificationChat ? null : conversationInfo.draftText);
    scrollController.addListener(_onChatScrolled);
    _messageSubscriptions.addAll([
      imLogic.revokedMessages.listen(_revokeMessageNotice),
      imLogic.deletedMessages
          .listen((event) => _removeMessageByID(event.clientMsgID)),
      imLogic.inputStateChangedSubject.listen((event) {
        if (event.conversationID != conversationInfo.conversationID ||
            event.userID != userID) {
          return;
        }
        _typingExpiry?.cancel();
        peerTyping.value = event.platformIDs?.isNotEmpty == true;
        if (peerTyping.value) {
          _typingExpiry =
              Timer(const Duration(seconds: 8), () => peerTyping.value = false);
        }
      }),
    ]);
    if (isSingleChat &&
        !isOfficialNotificationChat &&
        Get.isRegistered<ContactsLogic>()) {
      Get.find<ContactsLogic>().setProfilePresence(this, userID);
    }
    searchMessage = arguments['searchMessage'];
    nickname.value = conversationInfo.showName ?? '';
    faceUrl.value = conversationInfo.faceURL ?? '';
    _appearance.initialize();
    _setSdkSyncDataListener();
    _historyRecoveryWorker = ever(historyLoading, (bool loading) {
      if (!loading) {
        scheduleMicrotask(() {
          if (_sessionInactive) return;
          _historyRecovery.loadingSettled();
          if (isGroupChat) {
            unawaited(mentions.retryEntry().catchError((Object error) {
              if (!_sessionInactive)
                debugPrint('Mention lookup failed: $error');
            }));
          }
          messagePositionController.refreshViewport();
        });
      }
    });
    _messageSubscriptions.add(imLogic.historyRecoverySignals.listen((_) {
      _group.recover(resetAttempts: true);
      _backgroundMessageRecovery.restart(verifyCheckpoint: true);
      // Resume/connection catch-up can precede persistence. Recheck those
      // windows, while unrelated global wakes leave a healthy page alone.
      if (historyError.value == null) _recoverHistoryForSignal();
      _historyRecovery.request(resetAttempts: true, source: 'native_wake');
      _latestMessageRecovery.conversationChanged(resetAttempts: true);
    }));
    unawaited(onScrollToBottomLoad().whenComplete(() {
      entryTrace?.mark('initial_history_finished');
      // A retained conversation preview is not proof that history loaded.
      // Retry an initial empty/error response with the existing finite budget.
      _historyRecovery.request(source: 'initial_history_finished');
      // A cold local database can return an empty first page while the
      // conversation already advertises a persisted latest message.
      _latestMessageRecovery.conversationChanged();
    }));

    conversationSub = imLogic.conversationChangedSubject.listen((value) {
      final obj = value.firstWhereOrNull(
          (e) => e.conversationID == conversationInfo.conversationID);

      if (!_sessionInactive && obj != null) {
        conversationInfo = obj;
        _latestMessageRecovery.conversationChanged();
        _receipts.conversationChanged();
      }
    });

    _ownedMessageCallback = (Message message) {
      final active = !_sessionInactive;
      final currentChat = active && isCurrentChat(message);
      AssistantStreamLog.routed(message,
          active: active,
          currentChat: currentChat,
          assistantChat: isSingleChat && userID == 'assistant',
          buffering: bufferingLiveMessages);
      if (currentChat) {
        if (_messageRoute?.isCurrent == false &&
            !AssistantStreamChunk.isStreamMessage(message) &&
            message.contentType != MessageType.typing) {
          if (!_removedMessageIDs.contains(message.clientMsgID) &&
              !_timeline.containsMessage(message.clientMsgID)) {
            _timeline.bufferIncoming(message);
            _messagesWhileCovered = true;
            ++_coveredHistoryRevision;
          }
          return;
        }
        _appendLiveMessage(message);
      }
    };
    _messageSubscriptions.add(imLogic.chatMessageEvents
        .listen((event) => _ownedMessageCallback?.call(event.message)));

    _ownedReceiptCallback =
        (receipts) => _receipts.applyC2CReceipt(receipts, userID);
    _messageSubscriptions.add(imLogic.c2cReadReceipts
        .listen((receipts) => _ownedReceiptCallback?.call(receipts)));

    _group.initialize();
    _group.recover();

    friendInfoChangedSub = imLogic.friendInfoChangedSubject.listen((value) {
      if (!_sessionInactive && !isSingleChat) {
        _group.updateSenderAvatar(value.userID, value.faceURL);
        _group.refreshSenderIdentity(value.userID);
      }
      if (userID == value.userID) {
        nickname.value = value.getShowName();
        faceUrl.value = value.faceURL ?? '';

        for (var msg in messageList) {
          if (msg.sendID == value.userID) {
            msg.senderFaceUrl = value.faceURL;
            msg.senderNickname = value.nickname;
          }
        }

        messageList.refresh();
      }
    });

    selfInfoUpdatedSub = imLogic.selfInfoUpdatedSubject.listen((value) {
      if (!_sessionInactive && !isSingleChat) {
        _group.updateSenderAvatar(value.userID, value.faceURL);
        _group.refreshSenderIdentity(value.userID);
      }
      for (var msg in messageList) {
        if (msg.sendID == value.userID) {
          msg.senderFaceUrl = value.faceURL;
          msg.senderNickname = value.nickname;
        }
      }

      messageList.refresh();
    });

    _ownedSignalingCallback = (value) {
      if (!_sessionInactive && value.userID == userID) {
        _appendLiveMessage(value.message);
      }
    };
    imLogic.onSignalingMessage = _ownedSignalingCallback;

    entryTrace?.mark('init_finished');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sessionInactive) entryTrace?.mark('first_frame');
    });
    super.onInit();
  }

  Future chatSetup() => isOfficialNotificationChat
      ? Future<void>.value()
      : isSingleChat
          ? AppNavigator.startChatSetup(conversationInfo: conversationInfo)
          : AppNavigator.startGroupChatSetup(
              conversationInfo: conversationInfo);

  bool _reviewingPendingForward = false;

  Future<void> reviewPendingForward() async {
    final draft = pendingForward.draft.value;
    if (_sessionInactive ||
        draft == null ||
        pendingForward.sending.value ||
        _reviewingPendingForward) {
      return;
    }
    _reviewingPendingForward = true;
    try {
      final handled = await _forwarding.reviewPending(draft.messages,
          merged: draft.merged, mergeTitle: draft.mergeTitle);
      if (!_sessionInactive &&
          handled &&
          identical(pendingForward.draft.value, draft)) {
        pendingForward.cancel();
      }
    } finally {
      _reviewingPendingForward = false;
    }
  }

  Future<void> sendTextMsg() async {
    if (_reviewingPendingForward ||
        _sessionInactive ||
        sendingMuted ||
        isInvalidGroup ||
        pendingForward.sending.value) {
      return;
    }
    if (pendingForward.draft.value != null) {
      final sent = await pendingForward.send((draft) => _forwarding.sendPending(
          draft.messages, draft.recipient,
          merged: draft.merged, mergeTitle: draft.mergeTitle));
      if (!sent || _sessionInactive) return;
    }
    await _composer.sendTextMsg();
  }

  void mentionMessageSender(Message message) =>
      _composer.mentionMessageSender(message);
  Future<void> onLongPressAvatar(BuildContext context, Message message) =>
      _memberActions.open(
        message,
        showMenu: (actions, name) => context.mounted
            ? showChatMemberActionSheet(context,
                actions: actions, displayName: name)
            : Future.value(null),
        confirm: (action, name) => context.mounted
            ? confirmChatMemberAction(context,
                action: action, displayName: name)
            : Future.value(false),
      );
  void replyToMessage(Message message) {
    if (!isOfficialNotificationChat) _composer.replyToMessage(message);
  }

  void clearReply() => _composer.clearReply();
  bool canRevoke(Message message) =>
      !isOfficialNotificationChat && _revocation.canRevoke(message);
  Future<void> revokeMessage(Message message) => isOfficialNotificationChat
      ? Future<void>.value()
      : _revocation.revokeMessage(message);
  bool canForward(Message message) =>
      !isOfficialNotificationChat && _actions.canForward(message);
  bool canFavorite(Message message) =>
      !isOfficialNotificationChat && _favorites.canFavorite(message);
  Future<void> favoriteMessage(Message message) =>
      _favorites.favoriteMessage(message);
  Future<void> onTapFavorites() => _favorites.onTapFavorites();
  Future<void> forwardMessage(Message message) =>
      _forwarding.forwardMessage(message);
  Future sendPicture({required String path, bool sendNow = true}) =>
      _media.sendPicture(path: path, sendNow: sendNow);
  Future<Message?> prepareAssistantPicture(String path) =>
      _media.preparePicture(path);
  Future<void> sendForwardRemarkMsg(String content,
          {String? userId, String? groupId}) =>
      _forwarding.sendForwardRemarkMsg(content,
          userId: userId, groupId: groupId);
  Future<void> sendForwardMsg(Message message,
          {String? userId, String? groupId}) =>
      _forwarding.sendForwardMsg(message, userId: userId, groupId: groupId);

  void sendTypingMsg({bool focus = false}) async {
    if (_sameAccount && isSingleChat && !isOfficialNotificationChat) {
      OpenIM.iMManager.conversationManager.changeInputStates(
          conversationID: conversationInfo.conversationID, focus: focus);
    }
  }

  Future<void> onTapFormattedText() => _composer.onTapFormattedText();
  Future<void> onTapLocation() => _media.onTapLocation();
  Future<void> onTapEmoji() => _stickers.onTapEmoji();
  Future<void> onTapCard() => _forwarding.onTapCard();
  Future<void> sendCarte(
          {required String userID, String? nickname, String? faceURL}) =>
      _forwarding.sendCarte(
          userID: userID, nickname: nickname, faceURL: faceURL);

  Future<void> sendCustomMsg(
          {required String data,
          required String extension,
          required String description}) =>
      _delivery.sendCustomMessage(
          data: data, extension: extension, description: description);

  /// Prepared SDK attachments use the same delivery and retry state as text.
  Future sendPreparedMessage(Message message, {bool resetInput = false}) =>
      _sendMessage(message, resetInput: resetInput);

  Future _sendMessage(Message message,
          {String? userId,
          String? groupId,
          bool addToUI = true,
          bool resetInput = true,
          void Function(FavoriteSendResult)? favoriteResult}) =>
      _delivery.send(message,
          userId: userId,
          groupId: groupId,
          addToUI: addToUI,
          resetInput: resetInput,
          favoriteResult: favoriteResult);
  Future<void> markVoicePlayed(Message message) =>
      _voice.markVoicePlayed(message);
  bool canTranscribeVoice(Message message) =>
      _voice.canTranscribeVoice(message);
  Future<void> transcribeVoice(Message message) =>
      _voice.transcribeVoice(message);
  VoiceTranscriptionState? displayedVoiceTranscription(Message message) =>
      _voice.displayedVoiceTranscription(message);
  void markMessageAsRead(Message message, bool visible) =>
      _receipts.markMessageAsRead(message, visible);
  void _clearUnreadCount({bool leaving = false}) =>
      _receipts.clearUnreadCount(leaving: leaving);

  void closeToolbox() {
    forceCloseToolbox.addSafely(true);
  }

  Future<void> onTapAlbum() => _media.onTapAlbum();
  int get preparingMediaCount => _media.preparingCount.value;
  int get failedMediaPreparationCount => _media.failedPreparationCount.value;
  void retryMediaPreparation() => _media.retryPreparation();
  String? get mediaPreparationLabel => _media.preparationLabel;
  bool get hasFailedVideoPreparation => _media.hasFailedVideos;
  void retryOriginalVideoPreparation() =>
      _media.retryPreparation(originalVideos: true);
  void cancelMediaPreparation() => _media.cancelPreparation();
  Future<void> onTapFile() => _media.onTapFile();
  Future<void> onTapCamera() => _media.onTapCamera();
  Future<void> onTapRecord() => _voice.onTapRecord();
  Future<void> convertRecordedVoice(String path, int seconds) =>
      _voice.convertRecordedVoice(path, seconds);
  Future<void> sendRecordedVoice(String path, int seconds) =>
      _voice.sendRecordedVoice(path, seconds);
  Future<void> onTapAudio() => _media.onTapAudio();
  Future<bool> allowSendImageType(AssetEntity entity) =>
      _media.allowSendImageType(entity);
  Future<void> addPersonalSticker() => _stickers.addPersonalSticker();
  bool canAddMessageToStickers(Message message) =>
      !isOfficialNotificationChat &&
      ChatStickerController.messageStickerURL(message) != null;
  Future<void> addMessageToStickers(Message message) =>
      _stickers.addMessageToStickers(message);
  Future<void> sendPersonalSticker(PersonalSticker sticker) =>
      _stickers.sendPersonalSticker(sticker);

  Future<void> sendBuiltinSticker(ChatBuiltinSticker sticker) =>
      _stickers.sendBuiltinSticker(sticker);
  Future<void> sendDice() => _stickers.sendDice();
  Future<void> onTapDirectionalMessage() => _composer.onTapDirectionalMessage();
  TextSpan? directionalText() => _composer.directionalText();
  void onClearDirectional() => _composer.onClearDirectional();
  FundMessageData? fundMessageData(Message message) =>
      _funds.messageData(message);
  bool fundMessageClaimedByMe(FundMessageData message) =>
      _funds.claimedByMe(message);
  bool fundMessageStatusResolved(FundMessageData message) =>
      _funds.statusResolved(message);
  FundCardRecipient fundCardRecipient(FundMessageData message) =>
      _funds.cardRecipient(message);
  int? fundPacketCount(FundMessageData message) => _funds.packetCount(message);
  void setFundMessageVisible(Message message, bool visible) =>
      _funds.setVisible(message, visible);
  Future<void> onTapRedPacket() => _funds.openSend(isRedPacket: true);
  Future<void> onTapTransfer() => _funds.openSend(isRedPacket: false);
  List<ConfirmedFundCard> get confirmedFundCards => _sessionInactive
      ? const []
      : _funds.confirmedCards.cards.values.toList().reversed.map((card) {
          return ConfirmedFundCard(
              card.order, _funds.displayData(card.data), card.anchorMessageID);
        }).toList();
  Future<void> openConfirmedFundCard(FundMessageData data) =>
      _funds.openDetail(data);

  void parseClickEvent(Message msg) async {
    Logger.print(
        'parseClickEvent type:${msg.contentType} id:${msg.clientMsgID}',
        onlyConsole: true);
    if (msg.contentType == MessageType.custom) {
      final fund = fundMessageData(msg);
      if (fund != null) {
        await _funds.openDetail(fund, sourceMessage: msg);
        return;
      }
      if (!isSingleChat || isInBlacklist.value) return;
      try {
        final map = json.decode(msg.customElem?.data ?? '');
        if (map is! Map || map['customType'] != CustomMessageType.call) return;
        final data = map['data'];
        if (data is! Map) return;
        switch (data['type']) {
          case 'audio':
            callAudio();
            break;
          case 'video':
            callVideo();
            break;
        }
      } on FormatException {
        // Malformed records must not start a call of an assumed type.
        return;
      }

      return;
    }

    IMUtils.parseClickEvent(
      msg,
      onViewUserInfo: (userInfo) {
        viewUserInfo(userInfo,
            isCard: msg.isCardType,
            inviteCode: friendCardInviteCode(msg.cardElem?.ex));
      },
    );
  }

  void onTapLeftAvatar(Message message) {
    if (!isOfficialNotificationChat) _navigation.onTapLeftAvatar(message);
  }

  void onTapRightAvatar() {
    if (!isOfficialNotificationChat) _navigation.onTapRightAvatar();
  }

  void viewUserInfo(UserInfo userInfo,
          {bool isCard = false, String? inviteCode}) =>
      isOfficialNotificationChat
          ? null
          : _navigation.viewUserInfo(userInfo,
              isCard: isCard, inviteCode: inviteCode);
  void clickLinkText(String url, Object? type) =>
      _navigation.clickLinkText(url, type);
  Future<void> searchMentionID(String id) => _navigation.searchMentionID(id);

  Future<bool> exit() async {
    Get.back();

    return true;
  }

  Message indexOfMessage(int index, {bool calculate = true}) =>
      _timeline.indexOfMessage(index, calculate: calculate);

  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);

  @override
  void onClose() {
    entryTrace?.close();
    _entryReadyWorker?.dispose();
    _readDiagnostics.record('route_leave', _readDiagnosticState());
    // GetX sets isClosed before calling onClose; the account fence still owns
    // the final painted read and list refresh during synchronous disposal.
    if (!_chatClosing && _sameAccount) {
      _clearUnreadCount(leaving: true);
      ConversationRefreshEvents.publish(ConversationRefreshRequest(
          accountID: _chatAccountID,
          conversationID: conversationInfo.conversationID));
    }
    _chatClosing = true;
    messageArrivals.dispose();
    _dateJump.invalidate();
    _dateWindow.invalidate();
    _messageFocus.dispose();
    _messageRoute = null;
    messagePositionController.dispose();
    _messageSelectionWorker?.dispose();
    assistantStreams.dispose();
    messageSelection.dispose();
    _favorites.dispose();
    _latestScroll.close();
    newMessages.close();
    fundNotices.close();
    _timeline.close();
    _historyRecovery.close();
    _latestMessageRecovery.close();
    _backgroundMessageRecovery.close();
    _historyRecoveryWorker?.dispose();
    _receipts.close();
    messageReadUpdates.close();
    copyTextMap.clear();
    _ownedMessageCallback = null;
    _ownedReceiptCallback = null;
    if (identical(imLogic.onSignalingMessage, _ownedSignalingCallback)) {
      imLogic.onSignalingMessage = null;
    }
    _voice.dispose();
    _stickers.close();
    _media.close();
    _funds.close();
    _appearance.close();
    _typingExpiry?.cancel();
    _memberActions.close();
    _group.close();
    for (final subscription in _messageSubscriptions) {
      subscription.cancel();
    }
    _composer.dispose();
    if (Get.isRegistered<ContactsLogic>()) {
      Get.find<ContactsLogic>().setProfilePresence(this, null);
    }
    forceCloseToolbox.close();
    conversationSub.cancel();
    _delivery.close();
    friendInfoChangedSub.cancel();
    userStatusChangedSub?.cancel();
    selfInfoUpdatedSub?.cancel();
    connectionSub.cancel();
    scrollController.removeListener(_onChatScrolled);
    scrollController.dispose();
    refreshController.dispose();

    super.onClose();
  }

  String? getShowTime(Message message) => _timeline.getShowTime(message);

  void clearAllMessage() {
    _backgroundMessageRecovery.cancel();
    _latestMessageRecovery.cancel();
    ++_coveredHistoryRevision;
    _messagesWhileCovered = false;
    _messageFocus.cancel();
    _dateJump.invalidate();
    _dateWindow.invalidate();
    newMessages.reset();
    final ids = _timeline.clear();
    for (final id in ids) {
      _voice.removeMessage(id);
    }
    copyTextMap.clear();
    clearReply();
  }

  bool _confirmingMessageDeletion = false;
  Future<void> deleteMessage(Message message) async {
    final context = Get.context;
    if (_confirmingMessageDeletion ||
        _sessionInactive ||
        isOfficialNotificationChat ||
        context == null ||
        !context.mounted) return;
    _confirmingMessageDeletion = true;
    try {
      final confirmed = await MessageSelectionDeleteSheet.show(context, 1,
          singleMessage: true);
      if (!confirmed || _sessionInactive || !context.mounted) return;
      await _actions.deleteMessage(message);
    } finally {
      _confirmingMessageDeletion = false;
    }
  }

  Future<void> reloadChatBackground() => _appearance.reload();

  String get otherId => isSingleChat ? userID! : groupID!;

  void failedResend(Message message) {
    if (!isOfficialNotificationChat) _favorites.failedResend(message);
  }

  bool get havePermissionMute => _group.havePermissionMute;

  bool isNotificationType(Message message) =>
      ChatMessagePresentation.isNotification(message);

  Map<String, String> getAtMapping(Message message) =>
      _group.getAtMapping(message);

  void _checkInBlacklist() async {
    if (userID != null) {
      var list = await OpenIM.iMManager.friendshipManager.getBlacklist();
      var user = list.firstWhereOrNull((e) => e.userID == userID);
      isInBlacklist.value = user != null;
    }
  }

  Message resolveGroupNotice(Message message) => _group.noticeFor(message);

  String? getNewestNickname(Message message) {
    if (isSingleChat) return message.senderNickname;
    final remark = Get.isRegistered<ContactsLogic>()
        ? Get.find<ContactsLogic>().remarkFor(message.sendID)
        : null;
    return remark ?? _group.nicknameFor(message);
  }

  String? getNewestFaceURL(Message message) =>
      isSingleChat ? message.senderFaceUrl : _group.avatarFor(message);

  bool get isInvalidGroup => _group.isInvalidGroup;

  void _resetGroupAtType() {
    if (conversationInfo.groupAtType != GroupAtType.atNormal) {
      OpenIM.iMManager.conversationManager.resetConversationGroupAtType(
        conversationID: conversationInfo.conversationID,
      );
    }
  }

  void call() => _calling.call();
  void callDirectly(CallType type) => _calling.callDirectly(type);
  void callAudio() => _calling.callAudio();
  void callVideo() => _calling.callVideo();

  void onScrollToTop() {
    if (!_dateWindow.buffering) _timeline.flushBuffered();
  }

  String get markText {
    String? phoneNumber = imLogic.userInfo.value.phoneNumber;
    if (phoneNumber != null) {
      int start = phoneNumber.length > 4 ? phoneNumber.length - 4 : 0;
      final sub = phoneNumber.substring(start);
      return "${OpenIM.iMManager.userInfo.nickname!}$sub";
    }
    return OpenIM.iMManager.userInfo.nickname ?? '';
  }

  bool isFailedHintMessage(Message message) =>
      ChatMessagePresentation.isFailedHint(message);

  void sendFriendVerification() {
    if (_sessionInactive) return;
    _navigation.sendFriendVerification(
      userID: userID,
      nickname: nickname.value,
      faceURL: faceUrl.value,
    );
  }

  void _setSdkSyncDataListener() {
    final current = imLogic.currentSdkStatus;
    _awaitingInitialHistorySync = current != IMSdkStatus.syncEnded;
    if (current != null) syncStatus.value = current;
    connectionSub = imLogic.imSdkStatusPublishSubject.listen((value) {
      if (_sessionInactive) return;
      // Equal Rx values do not rebuild ChatMessageList. Invalidating on a
      // duplicate would discard its painted IDs without a replacement frame.
      final statusChanged = syncStatus.value != value.status;
      _readDiagnostics.record(
          'sync_status',
          {
            'previous': syncStatus.value.name,
            'next': value.status.name,
            'changed': statusChanged,
          },
          deduplicate: true);
      if (statusChanged) _receipts.invalidateViewport();
      syncStatus.value = value.status;
      if (value.status == IMSdkStatus.syncFailed) {
        _timeline.showLoadedLocalWindow();
      }
      if (statusChanged &&
          (value.status == IMSdkStatus.connecting ||
              value.status == IMSdkStatus.connectionFailed)) {
        _captureBackgroundGap();
      }
      if (statusChanged || value.status == IMSdkStatus.connectionSucceeded) {
        messagePositionController.refreshViewport();
      }
      if (value.status == IMSdkStatus.syncEnded) {
        _group.recover(resetAttempts: true);
        if (statusChanged) unawaited(_group.refreshProfileAfterSync());
        _backgroundMessageRecovery.restart(verifyCheckpoint: true);
        _historyRecovery.request(
            resetAttempts: statusChanged, source: 'sync_ended');
        _recoverHistoryForSignal();
        _awaitingInitialHistorySync = false;
        _latestMessageRecovery.conversationChanged(resetAttempts: true);
      } else if (value.status == IMSdkStatus.connectionSucceeded) {
        _group.recover(resetAttempts: true);
        _historyRecovery.request(
            resetAttempts: statusChanged, source: 'connection_succeeded');
        if (_backgroundMessageRecovery.hasCheckpoint) {
          _backgroundMessageRecovery.restart();
          unawaited(_loadHistoryForSyncEnd());
        }
      }
    });
  }

  bool get isSyncFailed => syncStatus.value == IMSdkStatus.syncFailed;

  String? get syncStatusStr {
    switch (syncStatus.value) {
      case IMSdkStatus.syncStart:
      case IMSdkStatus.synchronizing:
        return StrRes.synchronizing;
      case IMSdkStatus.syncFailed:
        return StrRes.syncFailed;
      default:
        return null;
    }
  }

  bool showBubbleBg(Message message) =>
      ChatMessagePresentation.showBubbleBackground(message);

  Future<bool> onScrollToBottomLoad() => _sessionInactive
      ? Future.value(false)
      : _dateWindow.seeking.value || _dateWindow.returning.value
          ? Future.value(historyHasMore.value)
          : _timeline.loadOlder();

  Future<bool> onScrollToTopLoad() => _sessionInactive
      ? Future.value(false)
      : _dateWindow.seeking.value || _dateWindow.returning.value
          ? Future.value(historyNewerHasMore.value)
          : _timeline.loadNewer();

  void retryHistory() {
    if (_sessionInactive) return;
    ChatHistoryDiagnostics.record(conversationInfo.conversationID, {
      'event': 'manual_continue',
      'scanLimited': historyScanLimited.value,
      'revision': historyWindowRevision.value
    });
    unawaited(_runHistoryRecovery(retry: true));
  }

  bool get _historyVisible {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return !_sessionInactive &&
        _messageRoute?.isCurrent != false &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  Future<bool> _loadHistoryForSyncEnd() => _runHistoryRecovery();

  void _recoverHistoryForSignal() {
    // Global retries can concern a different conversation. Live deliveries
    // and the latest-message owner already reconcile a healthy visible page.
    if (_awaitingInitialHistorySync ||
        !_timeline.hasLoadedHistory ||
        historyLoading.value ||
        _backgroundMessageRecovery.hasCheckpoint ||
        _messagesWhileCovered ||
        historyError.value != null) {
      unawaited(_loadHistoryForSyncEnd());
    }
  }

  Future<bool> _runHistoryRecovery({bool retry = false}) async {
    if (_sessionInactive) return false;
    ChatHistoryDiagnostics.record(conversationInfo.conversationID, {
      'event': 'recovery_request',
      'source': retry ? 'retry' : 'sync_or_resume',
      'revision': historyWindowRevision.value,
      'scanLimited': historyScanLimited.value,
    });
    if (!_historyVisible) {
      _messagesWhileCovered = true;
      ++_coveredHistoryRevision;
      return false;
    }
    if (!retry && historyError.value != null) {
      // Keep the failed paging/date action: a generic latest-page query would
      // silently replace its retry target and could move the reading window.
      _historyRecovery.request();
      return false;
    }
    final coveredRevision = _coveredHistoryRevision;
    _receipts.invalidateViewport();
    final recoverGap = !retry && _backgroundMessageRecovery.hasCheckpoint;
    final request = retry
        ? _dateWindow.retry()
        : recoverGap
            ? _backgroundMessageRecovery.recover()
            : _timeline.refresh();
    final window = historyWindowRevision.value;
    final recovered = await request;
    final applied = (!recoverGap || recovered) &&
        _historyVisible &&
        window == historyWindowRevision.value &&
        historyError.value == null;
    if (applied && coveredRevision == _coveredHistoryRevision) {
      _messagesWhileCovered = false;
    }
    // Require a new painted observation after the recovery request completes.
    if (!_sessionInactive) messageList.refresh();
    _historyRecovery.request();
    if (applied) _latestMessageRecovery.conversationChanged();
    return applied && !_dateWindow.buffering;
  }

  void _getGroupInfoAfterLoadMessage() {
    if (isGroupChat) {
      _group.recover();
    } else {
      _checkInBlacklist();
    }
  }

  Future<void> recommendFriendCarte(UserInfo userInfo) =>
      _forwarding.recommendFriendCarte(userInfo);

  @override
  void onDetached() {}

  @override
  void onHidden() => _captureBackgroundGap();

  @override
  void onInactive() {}

  @override
  void onPaused() {
    _captureBackgroundGap();
    _receipts.invalidateViewport();
    unawaited(_composer.saveDraft());
  }

  void _captureBackgroundGap() {
    if (_sessionInactive) return;
    // Even readers at the bottom can miss an entire offline interval. Keep
    // its boundary before native wake/live events can advance the latest row.
    _backgroundMessageRecovery.suspend();
  }

  @override
  void onResumed() {
    _group.recover(resetAttempts: true);
    unawaited(_loadHistoryForSyncEnd());
    _historyRecovery.request(resetAttempts: true, source: 'app_resumed');
    _latestMessageRecovery.conversationChanged(resetAttempts: true);
    _funds.refreshVisible();
  }
}
