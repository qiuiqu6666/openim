import 'dart:async';
import 'dart:convert';
import 'dart:developer';
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
import '../contacts/add_by_search/add_by_search_logic.dart';
import '../contacts/contacts_logic.dart';
import '../official_account/models/official_account.dart';
import '../official_account/presentation/official_account_timeline_policy.dart';
import '../ai_assistant/streaming/assistant_stream_chunk.dart';
import '../ai_assistant/streaming/assistant_stream_state.dart';
import '../group_features/data/group_feature_runtime.dart';
import '../group_features/models/group_feature_context.dart';
import 'composer/chat_composer_controller.dart';
import 'calling/chat_call_controller.dart';
import 'appearance/chat_appearance_controller.dart';
import 'favorites/chat_favorites_controller.dart';
import 'fund/chat_fund_controller.dart';
import 'fund/fund_card_recipient.dart';
import 'group_setup/group_member_list/group_member_list_logic.dart';
import 'group/chat_group_controller.dart';
import 'group/member_actions/chat_member_action_sheet.dart';
import 'group/member_actions/chat_member_actions_controller.dart';
import 'history/chat_timeline_controller.dart';
import 'history/chat_history_prefetcher.dart';
import 'history/date_jump/chat_date_jump_controller.dart';
import 'history/date_jump/chat_date_window_controller.dart';
import 'history/date_jump/widgets/chat_date_picker_dialog.dart';
import 'media/chat_media_controller.dart';
import 'messages/chat_delivery_controller.dart';
import 'messages/chat_message_actions.dart';
import 'messages/arrival/chat_message_arrival_controller.dart';
import 'messages/presentation/chat_message_presentation.dart';
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
  bool _chatClosing = false;
  String? _chatToken;
  String? _imToken;
  String? _chatRouteName;
  bool get _sameAccount =>
      _chatAccountID == OpenIM.iMManager.userID &&
      _chatToken == DataSp.chatToken &&
      _imToken == DataSp.imToken;
  bool get _sessionInactive => _chatClosing || isClosed || !_sameAccount;
  final assistantStreams = AssistantStreamState();
  late final messageArrivals =
      ChatMessageArrivalController(currentUserID: () => _chatAccountID);
  late final newMessages = ChatNewMessageTracker(
    currentUserID: () => OpenIM.iMManager.userID,
    isClosed: () => _sessionInactive,
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
    accountID: _chatAccountID,
    messageList: messageList,
    conversation: () => conversationInfo,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    groupStatus: () => groupInfo?.status,
    scrollBottom: scrollBottom,
    resetInput: (message) => _composer.resetAfterSend(message),
  );
  late final _receipts = ChatReadReceipts(
    messageList: messageList,
    conversation: () => conversationInfo,
    isClosed: () => _sessionInactive,
    canReadConversation: () => !messageArrivals.hasEntering,
    isActive: () =>
        Get.currentRoute == _chatRouteName &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed),
    isSessionActive: () => _sameAccount,
    onConversationRead: (request) =>
        imLogic.conversationReadRequestSubject.addSafely(request),
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
    conversationID: () => conversationInfo.conversationID,
    isClosed: () => _sessionInactive,
    sendingMuted: () => sendingMuted,
    isInvalidGroup: () => isInvalidGroup,
    voiceBusy: () => _voice.busy,
    sendMessage: (message, {addToUI = true, resetInput = true}) =>
        _sendMessage(message, addToUI: addToUI, resetInput: resetInput),
    stageMessage: (message) {
      if (!_sessionInactive) messageList.add(message);
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
    isClosed: () => _sessionInactive,
    canSend: () => !sendingMuted && !isInvalidGroup,
    userID: () => isSingleChat ? userID : null,
    groupID: () => isGroupChat ? groupID : null,
    recipientName: () => isSingleChat ? nickname.value : null,
    recipientFaceURL: () => isSingleChat ? faceUrl.value : null,
    closeToolbox: closeToolbox,
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
  late final ChatForwardingController _forwarding = ChatForwardingController(
    delivery: _delivery,
    messages: () => messageList,
    isClosed: () => _sessionInactive || isOfficialNotificationChat,
    isGroupChat: () => isGroupChat,
    nickname: () => nickname.value,
    faceUrl: () => faceUrl.value,
    canForward: canForward,
    closeToolbox: closeToolbox,
    onForwardNeedsReview: () => messageSelection.cancel(),
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
      nickname.value = name;
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

  final scrollController = ScrollController();
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
    _timeline.remove(id);
    if (messageList.isEmpty && scrollingCacheMessageList.isEmpty) {
      newMessages.reset();
    }
    _voice.removeMessage(id);
    copyTextMap.remove(id);
    if (quotedMessage.value?.clientMsgID == id) clearReply();
  }

  final forceCloseToolbox = PublishSubject<bool>();

  late ConversationInfo conversationInfo;
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
  );
  RxList<Message> get messageList => _timeline.messageList;
  List<Message> get scrollingCacheMessageList =>
      _timeline.scrollingCacheMessageList;
  RxBool get initialHistoryLoading => _timeline.initialHistoryLoading;
  RxBool get historyLoading => _timeline.historyLoading;
  RxnString get historyError => _timeline.historyError;
  RxBool get historyHasMore => _timeline.historyHasMore;
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
    if (!_sessionInactive) _messageRoute = route;
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

  final copyTextMap = <String?, String?>{};

  String? get userID => conversationInfo.userID;

  String? get groupID => conversationInfo.groupID;

  bool get isSingleChat => null != userID && userID!.trim().isNotEmpty;

  bool get isGroupChat => null != groupID && groupID!.trim().isNotEmpty;

  String get memberStr =>
      isSingleChat ? '' : 'groupMemberCountLabel'.trArgs(['$memberCount']);

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
        (senderId == userID ||
            senderId == OpenIM.iMManager.userID && receiverId == userID);
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

  bool onChatScrollNotification(ScrollNotification notification) {
    if (_sessionInactive) return false;
    if (notification.depth == 0 &&
        notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      messageArrivals.cancel();
      _latestScroll.cancel();
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
    if (distance > 1) newMessages.updateScrollOffset(distance);
  }

  void onChatViewportChanged(List<String> readIDs, double distanceFromLatest) {
    if (_sessionInactive) return;
    // A size transition is a clipped slice until its final layout. Only that
    // full-height painted frame may count as seeing the message or start burn.
    readIDs = readIDs.where((id) => !messageArrivals.isEntering(id)).toList();
    newMessages
        .updateScrollOffset(_dateWindow.buffering ? 2 : distanceFromLatest);
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

  void _appendLiveMessage(Message message) {
    // Online deltas have no history, read receipt, unread count or message menu.
    if (AssistantStreamChunk.isStreamMessage(message)) {
      if (!_sessionInactive && _isAssistantReply(message)) {
        final chunk = AssistantStreamChunk.tryParse(message);
        if (chunk != null) {
          _typingExpiry?.cancel();
          peerTyping.value = false;
          if (assistantStreams.accept(chunk) != null) {
            scrollBottom(force: false);
          }
        }
      }
      return;
    }
    if (!_sessionInactive && _isAssistantReply(message)) {
      assistantStreams.markFinalMessage(message);
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
        messageList.any((m) => m.clientMsgID == message.clientMsgID) ||
        scrollingCacheMessageList
            .any((m) => m.clientMsgID == message.clientMsgID)) {
      return;
    }
    if (scrollController.hasClients) {
      final distance =
          scrollController.offset - scrollController.position.minScrollExtent;
      if (distance > 1) newMessages.updateScrollOffset(distance);
    }
    final followLatest = !newMessages.awayFromLatest.value;
    if (_dateWindow.buffering) {
      newMessages.updateScrollOffset(2);
      newMessages.recordIncoming(message);
      scrollingCacheMessageList.add(message);
      return;
    }
    messageArrivals.register(message,
        enabled: followLatest &&
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
    messageList.add(message);
    if (followLatest) {
      scrollBottom(force: false);
    }
  }

  Future<List<Message>> searchMediaMessage() => _media.searchMediaMessage();

  @override
  void onReady() {
    if (_sessionInactive) return;
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
    conversationInfo = arguments['conversationInfo'];
    final account = arguments['officialAccount'];
    if (account is OfficialAccount &&
        account.userID == conversationInfo.userID) {
      _officialAccount = account;
    }
    _chatRouteName = Get.currentRoute;
    _chatAccountID = OpenIM.iMManager.userID;
    _chatToken = DataSp.chatToken;
    _imToken = DataSp.imToken;
    _timeline.initialize(prefetch: false);
    _reconcileAssistantReplies();
    _messageSelectionWorker = ever(messageList, (_) {
      messageSelection.sync();
      _reconcileAssistantReplies();
    });
    _composer.initialize(
        isOfficialNotificationChat ? null : conversationInfo.draftText);
    scrollController.addListener(_onChatScrolled);
    _messageSubscriptions.addAll([
      imLogic.revokedMessages
          .listen((event) => _removeMessageByID(event.clientMsgID)),
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
    unawaited(onScrollToBottomLoad());

    conversationSub = imLogic.conversationChangedSubject.listen((value) {
      final obj = value.firstWhereOrNull(
          (e) => e.conversationID == conversationInfo.conversationID);

      if (obj != null) {
        conversationInfo = obj;
        _receipts.conversationChanged();
      }
    });

    _ownedMessageCallback = (Message message) {
      if (!_sessionInactive && isCurrentChat(message)) {
        _appendLiveMessage(message);
      }
    };
    imLogic.onRecvNewMessage = _ownedMessageCallback;

    _ownedReceiptCallback =
        (receipts) => _receipts.applyC2CReceipt(receipts, userID);
    imLogic.onRecvC2CReadReceipt = _ownedReceiptCallback;

    _group.initialize();

    friendInfoChangedSub = imLogic.friendInfoChangedSubject.listen((value) {
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

    super.onInit();
  }

  Future chatSetup() => isOfficialNotificationChat
      ? Future<void>.value()
      : isSingleChat
          ? AppNavigator.startChatSetup(conversationInfo: conversationInfo)
          : AppNavigator.startGroupChatSetup(
              conversationInfo: conversationInfo);

  Future<void> sendTextMsg() => _composer.sendTextMsg();
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
      !isOfficialNotificationChat && _actions.canRevoke(message);
  Future<void> revokeMessage(Message message) => isOfficialNotificationChat
      ? Future<void>.value()
      : _actions.revokeMessage(message);
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

  void parseClickEvent(Message msg) async {
    log('parseClickEvent type:${msg.contentType} id:${msg.clientMsgID}');
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
    if (!_sessionInactive) _clearUnreadCount(leaving: true);
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
    _timeline.close();
    _receipts.close();
    if (identical(imLogic.onRecvNewMessage, _ownedMessageCallback)) {
      imLogic.onRecvNewMessage = null;
    }
    if (identical(imLogic.onRecvC2CReadReceipt, _ownedReceiptCallback)) {
      imLogic.onRecvC2CReadReceipt = null;
    }
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

  Future<void> deleteMessage(Message message) => isOfficialNotificationChat
      ? Future<void>.value()
      : _actions.deleteMessage(message);

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

  String? getNewestNickname(Message message) => message.senderNickname;
  String? getNewestFaceURL(Message message) => message.senderFaceUrl;

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
    AppNavigator.startAddContactsBySearch(searchType: SearchType.user);
  }

  void _setSdkSyncDataListener() {
    final current = imLogic.currentSdkStatus;
    if (current != null) syncStatus.value = current;
    connectionSub = imLogic.imSdkStatusPublishSubject.listen((value) {
      if (_sessionInactive) return;
      syncStatus.value = value.status;
      if (value.status == IMSdkStatus.syncEnded) {
        unawaited(_loadHistoryForSyncEnd());
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
    unawaited(_dateWindow.retry());
  }

  Future<void> _loadHistoryForSyncEnd() async {
    if (!_sessionInactive) await _timeline.refresh();
  }

  void _getGroupInfoAfterLoadMessage() {
    if (isGroupChat && ownerAndAdmin.isEmpty) {
      unawaited(_group.loadAfterHistory());
    } else {
      _checkInBlacklist();
    }
  }

  Future<void> recommendFriendCarte(UserInfo userInfo) =>
      _forwarding.recommendFriendCarte(userInfo);

  @override
  void onDetached() {}

  @override
  void onHidden() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {
    unawaited(_composer.saveDraft());
  }

  @override
  void onResumed() {
    _loadHistoryForSyncEnd();
    _funds.refreshVisible();
  }
}
