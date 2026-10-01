import 'package:file_picker/file_picker.dart';
import 'package:openim_common/src/widgets/chat/location_picker.dart';
import 'message_selection_page.dart';
import 'formatted_message_page.dart';
import 'package:openim_common/src/widgets/voice_capture_dialog.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sprintf/sprintf.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';
import 'package:openim_live/openim_live.dart';
import 'package:uuid/uuid.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../../routes/app_navigator.dart';
import '../contacts/select_contacts/select_contacts_logic.dart';
import '../contacts/contacts_logic.dart';
import '../contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'mention_id.dart';
import '../conversation/conversation_logic.dart';
import 'personal_sticker_store.dart';
import 'sticker_video_message.dart';
import 'group_setup/group_member_list/group_member_list_logic.dart';

class ChatLogic extends SuperController {
  late final voicePlayback = VoicePlaybackController(
    messages: () => messageList,
    onPlayed: markVoicePlayed,
  );
  final personalStickers = PersonalStickerStore();
  ({String url, String requestID})? _pendingSticker;
  final imLogic = Get.find<IMController>();
  final appLogic = Get.find<AppController>();
  final conversationLogic = Get.find<ConversationLogic>();
  final cacheLogic = Get.find<CacheController>();

  final inputCtrl = TextEditingController();
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  final refreshController = RefreshController();
  bool playOnce = false;
  final peerTyping = false.obs;
  final _messageSubscriptions = <StreamSubscription>[];
  Timer? _typingExpiry;

  final _removedMessageIDs = <String>{};
  void _removeMessageByID(String? id) {
    if (id == null) return;
    _removedMessageIDs.add(id);
    messageList.removeWhere((m) => m.clientMsgID == id);
    scrollingCacheMessageList.removeWhere((m) => m.clientMsgID == id);
    copyTextMap.remove(id);
    if (quotedMessage.value?.clientMsgID == id) clearReply();
  }

  final _muteRevision = 0.obs;
  Timer? _muteExpiry;
  void _refreshMute() {
    _muteRevision.value++;
    _muteExpiry?.cancel();
    final until = groupMembersInfo?.muteEndTime ?? 0;
    final seconds = until - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (seconds > 0)
      _muteExpiry =
          Timer(Duration(seconds: seconds + 1), () => _muteRevision.value++);
  }

  bool get sendingMuted {
    _muteRevision.value;
    return isGroupChat &&
        ((groupMembersInfo?.muteEndTime ?? 0) >
                DateTime.now().millisecondsSinceEpoch ~/ 1000 ||
            (groupMemberRoleLevel.value == GroupRoleLevel.member &&
                groupInfo?.status == 3));
  }

  final forceCloseToolbox = PublishSubject<bool>();
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();

  late ConversationInfo conversationInfo;
  Message? searchMessage;
  final nickname = ''.obs;
  final faceUrl = ''.obs;
  Timer? _debounce;
  Timer? _draftTimer;
  Future<void> _draftWrites = Future.value();
  final Map<String, String> _mentions = {};
  String _previousInput = '';
  bool _choosingMention = false;
  final messageList = <Message>[].obs;
  final tempMessages = <Message>[];
  final scaleFactor = Config.textScaleFactor.obs;
  final background = "".obs;
  final memberUpdateInfoMap = <String, GroupMembersInfo>{};
  final groupMessageReadMembers = <String, List<String>>{};
  final groupMemberRoleLevel = 1.obs;
  GroupInfo? groupInfo;
  GroupMembersInfo? groupMembersInfo;
  List<GroupMembersInfo> ownerAndAdmin = [];

  final isInGroup = true.obs;
  final memberCount = 0.obs;
  final privateMessageList = <Message>[];
  final isInBlacklist = false.obs;

  final scrollingCacheMessageList = <Message>[];
  final announcement = ''.obs;
  final announcementVersion = ''.obs;
  late StreamSubscription conversationSub;
  late StreamSubscription memberAddSub;
  late StreamSubscription memberDelSub;
  late StreamSubscription joinedGroupAddedSub;
  late StreamSubscription joinedGroupDeletedSub;
  late StreamSubscription memberInfoChangedSub;
  late StreamSubscription groupInfoUpdatedSub;
  late StreamSubscription friendInfoChangedSub;
  StreamSubscription? userStatusChangedSub;
  StreamSubscription? selfInfoUpdatedSub;

  late StreamSubscription connectionSub;
  final syncStatus = IMSdkStatus.syncEnded.obs;
  int? lastMinSeq;

  final showCallingMember = false.obs;

  bool _isReceivedMessageWhenSyncing = false;
  bool _isStartSyncing = false;
  bool _isFirstLoad = true;

  final copyTextMap = <String?, String?>{};
  final quotedMessage = Rxn<Message>();

  String? groupOwnerID;

  final _pageSize = 40;

  RTCBridge? get rtcBridge => PackageBridge.rtcBridge;

  bool get rtcIsBusy => rtcBridge?.hasConnection == true;

  String? get userID => conversationInfo.userID;

  String? get groupID => conversationInfo.groupID;

  bool get isSingleChat => null != userID && userID!.trim().isNotEmpty;

  bool get isGroupChat => null != groupID && groupID!.trim().isNotEmpty;

  String get memberStr =>
      isSingleChat ? '' : 'groupMemberCountLabel'.trArgs(['$memberCount']);

  String? get senderName => isSingleChat
      ? OpenIM.iMManager.userInfo.nickname
      : groupMembersInfo?.nickname;

  bool get isAdminOrOwner =>
      groupMemberRoleLevel.value == GroupRoleLevel.admin ||
      groupMemberRoleLevel.value == GroupRoleLevel.owner;

  final directionalUsers = <GroupMembersInfo>[].obs;

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

  void scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      scrollController.jumpTo(0);
    });
  }

  Future<List<Message>> searchMediaMessage() async {
    final messageList = await OpenIM.iMManager.messageManager
        .searchLocalMessages(
            conversationID: conversationInfo.conversationID,
            messageTypeList: [MessageType.picture, MessageType.video],
            count: 500);
    return messageList.searchResultItems?.first.messageList?.reversed
            .toList() ??
        [];
  }

  @override
  void onReady() {
    _resetGroupAtType();
    _clearUnreadCount();

    scrollController.addListener(() {
      focusNode.unfocus();
    });
    super.onReady();
  }

  @override
  void onInit() {
    var arguments = Get.arguments;
    conversationInfo = arguments['conversationInfo'];
    _restoreDraft(conversationInfo.draftText);
    _messageSubscriptions.addAll([
      imLogic.revokedMessages
          .listen((event) => _removeMessageByID(event.clientMsgID)),
      imLogic.deletedMessages
          .listen((event) => _removeMessageByID(event.clientMsgID)),
      imLogic.inputStateChangedSubject.listen((event) {
        if (event.conversationID != conversationInfo.conversationID ||
            event.userID != userID) return;
        _typingExpiry?.cancel();
        peerTyping.value = event.platformIDs?.isNotEmpty == true;
        if (peerTyping.value)
          _typingExpiry =
              Timer(const Duration(seconds: 8), () => peerTyping.value = false);
      }),
    ]);
    if (isSingleChat && Get.isRegistered<ContactsLogic>()) {
      Get.find<ContactsLogic>().setProfilePresence(this, userID);
    }
    searchMessage = arguments['searchMessage'];
    nickname.value = conversationInfo.showName ?? '';
    faceUrl.value = conversationInfo.faceURL ?? '';
    _initChatConfig();
    _setSdkSyncDataListener();

    conversationSub = imLogic.conversationChangedSubject.listen((value) {
      final obj = value.firstWhereOrNull(
          (e) => e.conversationID == conversationInfo.conversationID);

      if (obj != null) {
        conversationInfo = obj;
      }
    });

    imLogic.onRecvNewMessage = (Message message) async {
      if (isCurrentChat(message)) {
        if (message.contentType == MessageType.typing) {
        } else {
          if (!_removedMessageIDs.contains(message.clientMsgID) &&
              !messageList.contains(message) &&
              !scrollingCacheMessageList.contains(message)) {
            _isReceivedMessageWhenSyncing = true;
            if (scrollController.offset != 0) {
              scrollingCacheMessageList.add(message);
            } else {
              messageList.add(message);
              scrollBottom();
            }
          }
        }
      }
    };

    imLogic.onRecvC2CReadReceipt = (List<ReadReceiptInfo> list) {
      try {
        for (var readInfo in list) {
          if (readInfo.userID == userID) {
            for (var e in messageList) {
              if (readInfo.msgIDList?.contains(e.clientMsgID) == true) {
                e.isRead = true;
                e.hasReadTime = _timestamp;
              }
            }
          }
        }
        messageList.refresh();
      } catch (e) {}
    };

    joinedGroupAddedSub = imLogic.joinedGroupAddedSubject.listen((event) {
      if (event.groupID == groupID) {
        isInGroup.value = true;
        _queryGroupInfo();
      }
    });

    joinedGroupDeletedSub = imLogic.joinedGroupDeletedSubject.listen((event) {
      if (event.groupID == groupID) {
        isInGroup.value = false;
        inputCtrl.clear();
      }
    });

    memberAddSub = imLogic.memberAddedSubject.listen((info) {
      var groupId = info.groupID;
      if (groupId == groupID) {
        _putMemberInfo([info]);
      }
    });

    memberDelSub = imLogic.memberDeletedSubject.listen((info) {
      if (info.groupID == groupID && info.userID == OpenIM.iMManager.userID) {
        isInGroup.value = false;
        inputCtrl.clear();
      }
    });

    memberInfoChangedSub = imLogic.memberInfoChangedSubject.listen((info) {
      if (info.groupID == groupID) {
        if (info.userID == OpenIM.iMManager.userID) {
          groupMemberRoleLevel.value = info.roleLevel ?? GroupRoleLevel.member;
          groupMembersInfo = info;
          _refreshMute();
          ();
        }
        _putMemberInfo([info]);

        final index = ownerAndAdmin
            .indexWhere((element) => element.userID == info.userID);
        if (info.roleLevel == GroupRoleLevel.member) {
          if (index > -1) {
            ownerAndAdmin.removeAt(index);
          }
        } else if (info.roleLevel == GroupRoleLevel.admin ||
            info.roleLevel == GroupRoleLevel.owner) {
          if (index == -1) {
            ownerAndAdmin.add(info);
          } else {
            ownerAndAdmin[index] = info;
          }
        }

        for (var msg in messageList) {
          if (msg.sendID == info.userID) {
            if (msg.isNotificationType) {
              final map = json.decode(msg.notificationElem!.detail!);
              final ntf = GroupNotification.fromJson(map);
              ntf.opUser?.nickname = info.nickname;
              ntf.opUser?.faceURL = info.faceURL;
              msg.notificationElem?.detail = jsonEncode(ntf);
            } else {
              msg.senderFaceUrl = info.faceURL;
              msg.senderNickname = info.nickname;
            }
          }
        }

        messageList.refresh();
      }
    });

    groupInfoUpdatedSub = imLogic.groupInfoUpdatedSubject.listen((value) {
      if (groupID == value.groupID) {
        groupInfo = value;
        announcement.value = value.notification ?? '';
        announcementVersion.value =
            value.notificationUpdateTime?.toString() ?? '';
        _refreshMute();
        nickname.value = value.groupName ?? '';
        faceUrl.value = value.faceURL ?? '';
        memberCount.value = value.memberCount ?? 0;
      }
    });

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

    inputCtrl.addListener(() {
      _inputChanged();
      sendTypingMsg(focus: true);
      if (_debounce?.isActive ?? false) _debounce?.cancel();

      _debounce = Timer(1.seconds, () {
        sendTypingMsg(focus: false);
      });
    });

    focusNode.addListener(() {
      focusNodeChanged(focusNode.hasFocus);
    });

    imLogic.onSignalingMessage = (value) {
      if (value.userID == userID) {
        messageList.add(value.message);
        scrollBottom();
      }
    };

    super.onInit();
  }

  Future chatSetup() => isSingleChat
      ? AppNavigator.startChatSetup(conversationInfo: conversationInfo)
      : AppNavigator.startGroupChatSetup(conversationInfo: conversationInfo);

  void _putMemberInfo(List<GroupMembersInfo>? list) {
    list?.forEach((member) {
      memberUpdateInfoMap[member.userID!] = member;
    });

    messageList.refresh();
  }

  void _restoreDraft(String? draft) {
    if (draft == null || draft.isEmpty) return;
    var text = draft;
    try {
      final data = jsonDecode(draft);
      if (data is Map && data['text'] is String) {
        text = data['text'];
        if (data['mentions'] is Map) {
          for (final entry in (data['mentions'] as Map).entries) {
            if (entry.key is String && entry.value is String) {
              _mentions[entry.key] = entry.value;
            }
          }
        }
      }
    } catch (_) {}
    inputCtrl.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    _previousInput = text;
  }

  void _saveDraft() {
    final text = inputCtrl.text;
    final draft = text.isEmpty
        ? ''
        : jsonEncode({
            'text': text,
            'mentions': _mentions,
          });
    final id = conversationInfo.conversationID;
    _draftWrites = _draftWrites.then((_) async {
      await OpenIM.iMManager.conversationManager
          .setConversationDraft(conversationID: id, draftText: draft);
    }).catchError((Object error) {
      Logger.print('Save conversation draft failed: $error');
    });
  }

  void _inputChanged() {
    final text = inputCtrl.text;
    if (text == _previousInput) return;
    final old = _previousInput;
    _previousInput = text;
    _mentions.removeWhere((id, name) => !text.contains('@$name '));
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
    final cursor = inputCtrl.selection.baseOffset;
    if (isGroupChat &&
        !_choosingMention &&
        text.length == old.length + 1 &&
        cursor > 0 &&
        text[cursor - 1] == '@') {
      _selectMentions(cursor - 1);
    }
  }

  Future<void> _selectMentions(int start) async {
    if (groupInfo == null) return;
    _choosingMention = true;
    focusNode.unfocus();
    try {
      final selected =
          await AppNavigator.startGroupMemberList<List<GroupMembersInfo>>(
              groupInfo: groupInfo!, opType: GroupMemberOpType.at);
      if (isClosed || selected == null || selected.isEmpty) return;
      final text = inputCtrl.text;
      if (start >= text.length || text[start] != '@') return;
      final inserted = selected
          .where((member) => member.userID != null)
          .map((member) => '@${member.nickname ?? member.userID} ')
          .join();
      inputCtrl.value = TextEditingValue(
        text: text.replaceRange(start, start + 1, inserted),
        selection: TextSelection.collapsed(offset: start + inserted.length),
      );
      for (final member in selected) {
        if (member.userID != null) {
          _mentions[member.userID!] = member.nickname ?? member.userID!;
        }
      }
      _saveDraft();
    } catch (error) {
      IMViews.showToast(error.toString());
    } finally {
      _choosingMention = false;
      if (!isClosed) focusNode.requestFocus();
    }
  }

  void mentionMessageSender(Message message) {
    final userID = message.sendID;
    if (isClosed || !isGroupChat || _choosingMention ||
        userID == null || userID.isEmpty || userID == OpenIM.iMManager.userID) {
      return;
    }
    if (sendingMuted) {
      IMViews.showToast(StrRes.youMuted);
      return;
    }
    final name = message.senderNickname?.trim().isNotEmpty == true
        ? message.senderNickname!.trim() : userID;
    final text = inputCtrl.text;
    final selection = inputCtrl.selection;
    final valid = selection.isValid && selection.end <= text.length;
    final start = valid ? selection.start : text.length;
    final end = valid ? selection.end : text.length;
    final inserted = '@$name ';
    _choosingMention = true;
    try {
      inputCtrl.value = TextEditingValue(
        text: text.replaceRange(start, end, inserted),
        selection: TextSelection.collapsed(offset: start + inserted.length),
      );
      _mentions[userID] = name;
      _saveDraft();
    } finally {
      _choosingMention = false;
    }
    closeToolbox();
    focusNode.requestFocus();
  }

  void sendTextMsg() async {
    if (sendingMuted) {
      IMViews.showToast(StrRes.youMuted);
      return;
    }
    var content = IMUtils.safeTrim(inputCtrl.text);
    if (content.isEmpty) return;
    final quote = quotedMessage.value;
    try {
      final mentions = _mentions.entries
          .where((entry) => inputCtrl.text.contains('@${entry.value} '))
          .toList();
      final message = isGroupChat && mentions.isNotEmpty
          ? await OpenIM.iMManager.messageManager.createTextAtMessage(
              text: content,
              atUserIDList: mentions.map((entry) => entry.key).toList(),
              atUserInfoList: mentions
                  .map((entry) => AtUserInfo(
                      atUserID: entry.key, groupNickname: entry.value))
                  .toList(),
              quoteMessage: quote,
            )
          : quote == null
              ? await OpenIM.iMManager.messageManager
                  .createTextMessage(text: content)
              : await OpenIM.iMManager.messageManager
                  .createQuoteMessage(text: content, quoteMsg: quote);
      quotedMessage.value = null;
      _sendMessage(message);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  void replyToMessage(Message message) {
    quotedMessage.value = message;
    focusNode.requestFocus();
  }

  void clearReply() => quotedMessage.value = null;

  bool canRevoke(Message message) {
    final sentAt = message.sendTime;
    return message.sendID == OpenIM.iMManager.userID &&
        message.status == MessageStatus.succeeded &&
        sentAt != null &&
        DateTime.now().millisecondsSinceEpoch - sentAt <
            const Duration(minutes: 2).inMilliseconds;
  }

  Future<void> revokeMessage(Message message) async {
    final clientMsgID = message.clientMsgID;
    if (clientMsgID == null || !canRevoke(message)) return;
    try {
      await OpenIM.iMManager.messageManager.revokeMessage(
        conversationID: conversationInfo.conversationID,
        clientMsgID: clientMsgID,
      );
      _removeMessageByID(clientMsgID);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  bool canForward(Message message) =>
      message.status == MessageStatus.succeeded &&
      message.attachedInfoElem?.isPrivateChat != true &&
      [
        MessageType.text,
        MessageType.atText,
        MessageType.advancedText,
        MessageType.picture,
        MessageType.video,
        MessageType.voice,
        MessageType.file,
        MessageType.card,
        MessageType.location,
        MessageType.customFace,
        MessageType.merger,
        MessageType.quote
      ].contains(message.contentType);

  Future<void> forwardMessage(Message message) async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      ex: IMUtils.parseMsg(message, isConversation: true),
    );
    if (result == null) return;
    try {
      for (final contact in result['checkedList']) {
        final userId = IMUtils.convertCheckedToUserID(contact);
        final groupId = IMUtils.convertCheckedToGroupID(contact);
        final forwarded = await OpenIM.iMManager.messageManager
            .createForwardMessage(message: message);
        await _sendMessage(forwarded, userId: userId, groupId: groupId);
      }
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future sendPicture({required String path, bool sendNow = true}) async {
    final file = await IMUtils.compressImageAndGetFile(File(path));

    var message =
        await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
      imagePath: file!.path,
    );

    if (sendNow) {
      return _sendMessage(message);
    } else {
      messageList.add(message);
      tempMessages.add(message);
    }
  }

  sendForwardRemarkMsg(
    String content, {
    String? userId,
    String? groupId,
  }) async {
    final message = await OpenIM.iMManager.messageManager.createTextMessage(
      text: content,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  sendForwardMsg(
    Message originalMessage, {
    String? userId,
    String? groupId,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createForwardMessage(
      message: originalMessage,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  void sendTypingMsg({bool focus = false}) async {
    if (isSingleChat) {
      OpenIM.iMManager.conversationManager.changeInputStates(
          conversationID: conversationInfo.conversationID, focus: focus);
    }
  }

  Future<void> onTapFormattedText() async {
    closeToolbox();
    final quote = quotedMessage.value;
    final result =
        await Get.to<({String text, List<RichMessageInfo> entities})>(
            () => FormattedMessagePage(initialText: inputCtrl.text));
    if (result == null || isClosed) return;
    try {
      final message = quote == null
          ? await OpenIM.iMManager.messageManager.createAdvancedTextMessage(
              text: result.text, list: result.entities)
          : await OpenIM.iMManager.messageManager.createAdvancedQuoteMessage(
              text: result.text, list: result.entities, quoteMsg: quote);
      if (!isClosed) {
        await _sendMessage(message);
        inputCtrl.clear();
        clearReply();
      }
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> onTapLocation() async {
    closeToolbox();
    final point =
        await Get.to<({double latitude, double longitude, String description})>(
            () => const ChatLocationPicker());
    if (point == null || isClosed) return;
    try {
      final message = await OpenIM.iMManager.messageManager
          .createLocationMessage(
              latitude: point.latitude,
              longitude: point.longitude,
              description: point.description.isEmpty
                  ? StrRes.location
                  : point.description);
      if (!isClosed) await _sendMessage(message);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> onTapEmoji() async {
    closeToolbox();
    try {
      final files = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'gif', 'webp', 'jpg']);
      final file = files?.files.first;
      if (file?.path == null || isClosed) return;
      if (file!.size > 10 * 1024 * 1024) {
        IMViews.showToast('sdkEmojiTooLarge'.tr);
        return;
      }
      final accepted =
          await Get.dialog<bool>(CustomDialog(title: 'sdkSendEmojiConfirm'.tr));
      if (accepted != true || isClosed) return;
      final result = await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.uploadFile(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              filePath: file.path!,
              fileName: file.name));
      final data = result is String ? jsonDecode(result) : result;
      final url = data['url'] as String;
      final message = await OpenIM.iMManager.messageManager
          .createFaceMessage(index: -1, data: url);
      if (!isClosed) await _sendMessage(message);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> mergeForward(Message initial) async {
    final selection = await Get.to<List<Message>>(() => MessageSelectionPage(
        messages: messageList.where(canForward).toList(),
        initialID: initial.clientMsgID));
    if (selection == null || selection.isEmpty || isClosed) return;
    try {
      selection.sort((a, b) => (a.sendTime ?? 0).compareTo(b.sendTime ?? 0));
      final targets = await AppNavigator.startSelectContacts(
          action: SelAction.forward, ex: 'sdkMergedHistory'.tr);
      if (targets == null || isClosed) return;
      for (final contact in targets['checkedList']) {
        final message = await OpenIM.iMManager.messageManager
            .createMergerMessage(
                messageList: selection,
                title: '${nickname.value} · ${'sdkMergedHistory'.tr}',
                summaryList: selection
                    .take(3)
                    .map((m) =>
                        '${m.senderNickname ?? ''}: ${IMUtils.parseMsg(m)}')
                    .toList());
        await _sendMessage(message,
            userId: IMUtils.convertCheckedToUserID(contact),
            groupId: IMUtils.convertCheckedToGroupID(contact));
      }
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> onTapCard() async {
    closeToolbox();
    final selected = await AppNavigator.startSelectContacts(
      action: SelAction.carte,
      cardRecipientName: nickname.value,
      cardRecipientFaceURL: faceUrl.value,
      cardRecipientIsGroup: isGroupChat,
    );
    if (isClosed ||
        selected is! UserInfo ||
        selected.userID?.isNotEmpty != true) {
      return;
    }
    try {
      await sendCarte(
        userID: selected.userID!,
        nickname: selected.nickname,
        faceURL: selected.faceURL,
      );
    } catch (error) {
      Logger.print('Send contact card failed: $error');
      IMViews.showToast(StrRes.sendFailed);
    }
  }

  Future<void> sendCarte({
    required String userID,
    String? nickname,
    String? faceURL,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCardMessage(
      userID: userID,
      nickname: nickname?.trim().isNotEmpty == true ? nickname! : userID,
      faceURL: faceURL,
    );
    await _sendMessage(message);
  }

  void sendCustomMsg({
    required String data,
    required String extension,
    required String description,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: data,
      extension: extension,
      description: description,
    );
    _sendMessage(message);
  }

  Future _sendMessage(
    Message message, {
    String? userId,
    String? groupId,
    bool addToUI = true,
  }) {
    log('send : ${json.encode(message)}');
    userId = IMUtils.emptyStrToNull(userId);
    groupId = IMUtils.emptyStrToNull(groupId);
    if (null == userId && null == groupId ||
        userId == userID && userId != null ||
        groupId == groupID && groupId != null) {
      if (addToUI) {
        messageList.add(message);
        scrollBottom();
      }
    }
    Logger.print('uid:$userID userId:$userId gid:$groupID groupId:$groupId');
    _reset(message);
    bool useOuterValue = null != userId || null != groupId;

    final recvUserID = useOuterValue ? userId : userID;
    message.recvID = recvUserID;

    return OpenIM.iMManager.messageManager
        .sendMessage(
          message: message,
          userID: recvUserID,
          groupID: useOuterValue ? groupId : groupID,
          offlinePushInfo: Config.offlinePushInfo,
        )
        .then((value) => _sendSucceeded(message, value))
        .catchError(
            (error, _) => _senFailed(message, groupId, userId, error, _))
        .whenComplete(() => _completed());
  }

  void _sendSucceeded(Message oldMsg, Message newMsg) {
    Logger.print('message send success----');
    oldMsg.update(newMsg);
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: oldMsg.clientMsgID!,
      value: true,
    ));
  }

  void _senFailed(
      Message message, String? groupId, String? userId, error, stack) async {
    Logger.print(
        'message send failed userID: $userId groupId:$groupId, catch error :$error  $stack');
    message.status = MessageStatus.failed;
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: false,
    ));
    if (error is PlatformException) {
      int code = int.tryParse(error.code) ?? 0;
      if (isSingleChat) {
        int? customType;
        if (code == SDKErrorCode.hasBeenBlocked) {
          customType = CustomMessageType.blockedByFriend;
        } else if (code == SDKErrorCode.notFriend) {
          customType = CustomMessageType.deletedByFriend;
        }
        if (null != customType) {
          final hintMessage = (await OpenIM.iMManager.messageManager
              .createFailedHintMessage(type: customType))
            ..status = 2
            ..isRead = true;
          if (userId != null) {
            if (userId == userID) {
              messageList.add(hintMessage);
            }
          } else {
            messageList.add(hintMessage);
          }
          OpenIM.iMManager.messageManager.insertSingleMessageToLocalStorage(
            message: hintMessage,
            receiverID: userId ?? userID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      } else {
        if ((code == SDKErrorCode.userIsNotInGroup ||
                code == SDKErrorCode.groupDisbanded) &&
            null == groupId) {
          final status = groupInfo?.status;
          final hintMessage = (await OpenIM.iMManager.messageManager
              .createFailedHintMessage(
                  type: status == 2
                      ? CustomMessageType.groupDisbanded
                      : CustomMessageType.removedFromGroup))
            ..status = 2
            ..isRead = true;
          messageList.add(hintMessage);
          OpenIM.iMManager.messageManager.insertGroupMessageToLocalStorage(
            message: hintMessage,
            groupID: groupID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      }
    }
  }

  void _reset(Message message) {
    if (message.contentType == MessageType.text ||
        message.contentType == MessageType.atText ||
        message.contentType == MessageType.quote) {
      inputCtrl.clear();
      _mentions.clear();
      _draftTimer?.cancel();
      _saveDraft();
    }
  }

  void _completed() {
    messageList.refresh();
  }

  Future<void> markVoicePlayed(Message message) async {
    Map<String, dynamic> extra = {};
    try {
      extra = Map<String, dynamic>.from(jsonDecode(message.localEx ?? '{}'));
    } catch (_) {}
    if (extra['voiceHeard'] != true) {
      extra['voiceHeard'] = true;
      final encoded = jsonEncode(extra);
      await OpenIM.iMManager.messageManager.setMessageLocalEx(
          conversationID: conversationInfo.conversationID,
          clientMsgID: message.clientMsgID!,
          localEx: encoded);
      message.localEx = encoded;
    }
    if (!isClosed) await _markMessageAsRead(message);
  }

  void markMessageAsRead(Message message, bool visible) async {
    Logger.print('markMessageAsRead: ${message.textElem?.content}, $visible');
    if (visible &&
        message.contentType! < 1000 &&
        message.contentType! != MessageType.voice) {
      var data = IMUtils.parseCustomMessage(message);
      if (null != data && data['viewType'] == CustomMessageType.call) {
        Logger.print('markMessageAsRead: call message $data');
        return;
      }
      _markMessageAsRead(message);
    }
  }

  final _readInFlight = <String>{};
  Future<void> _markMessageAsRead(Message message) async {
    final id = message.clientMsgID;
    if (id == null ||
        message.isRead == true ||
        message.sendID == OpenIM.iMManager.userID ||
        !_readInFlight.add(id)) return;
    try {
      if (message.attachedInfoElem?.isPrivateChat == true) {
        await OpenIM.iMManager.messageManager.markMessagesAsReadByMsgID(
            conversationID: conversationInfo.conversationID,
            messageIDList: [id]);
      } else {
        await OpenIM.iMManager.conversationManager
            .markConversationMessageAsRead(
                conversationID: conversationInfo.conversationID);
      }
      if (isClosed) return;
      message.isRead = true;
      message.hasReadTime = _timestamp;
      if (message.attachedInfoElem?.isPrivateChat == true)
        message.attachedInfoElem?.hasReadTime = _timestamp;
      messageList.refresh();
    } catch (error) {
      Logger.print('Mark read failed: $error');
    } finally {
      _readInFlight.remove(id);
    }
  }

  _clearUnreadCount() {
    if (conversationInfo.unreadCount > 0) {
      OpenIM.iMManager.conversationManager.markConversationMessageAsRead(
          conversationID: conversationInfo.conversationID);
    }
  }

  void closeToolbox() {
    forceCloseToolbox.addSafely(true);
  }

  void onTapAlbum() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(Get.context!,
        pickerConfig: AssetPickerConfig(
            requestType: RequestType.common,
            sortPathsByModifiedDate: true,
            filterOptions: PMFilter.defaultValue(containsPathModified: true),
            selectPredicate: (_, entity, isSelected) async {
              if (entity.type == AssetType.image) {
                if (await allowSendImageType(entity)) {
                  return true;
                }

                IMViews.showToast(StrRes.supportsTypeHint);

                return false;
              }

              if (entity.videoDuration > const Duration(seconds: 5 * 60)) {
                IMViews.showToast(
                    sprintf(StrRes.selectVideoLimit, [5]) + StrRes.minute);
                return false;
              }
              return true;
            }));
    if (null != assets) {
      for (var asset in assets) {
        try {
          await _handleAssets(asset, sendNow: false);
        } catch (_) {
          IMViews.showToast(StrRes.sendFailed);
        }
      }

      for (var msg in tempMessages) {
        await _sendMessage(msg, addToUI: false);
      }

      tempMessages.clear();
    }
  }

  bool _pickingAttachment = false;
  Future<File> _retainAttachment(String path) async {
    final name = path.split(Platform.pathSeparator).last;
    final directory = Directory('${Config.cachePath}/outgoing_media');
    await directory.create(recursive: true);
    return File(path).copy(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$name');
  }

  Future<void> onTapFile() => _pickAttachment(false);
  Future<void> onTapCamera() async {
    if (_pickingAttachment) return;
    _pickingAttachment = true;
    try {
      final asset = await CameraPicker.pickFromCamera(Get.context!,
          pickerConfig: const CameraPickerConfig(
              enableRecording: true,
              enableAudio: true,
              maximumRecordingDuration: Duration(seconds: 60)));
      if (asset != null && !isClosed) await _handleAssets(asset);
    } catch (_) {
      IMViews.showToast(StrRes.sendFailed);
    } finally {
      _pickingAttachment = false;
    }
  }

  Future<void> onTapRecord() async {
    final result = await Get.dialog<Map<String, dynamic>>(
        const VoiceCaptureDialog(),
        barrierDismissible: false);
    if (result == null || isClosed) return;
    try {
      final message = await OpenIM.iMManager.messageManager
          .createSoundMessageFromFullPath(
              soundPath: result['path'], duration: result['duration']);
      await _sendMessage(message);
    } catch (_) {
      IMViews.showToast(StrRes.sendFailed);
    }
  }

  Future<void> addPersonalSticker() async {
    if (isClosed) return;
    try {
      var pending = _pendingSticker;
      if (pending != null) {
        final retry = await Get.dialog<bool>(AlertDialog(
          title: const Text('上次收藏未完成'),
          content: const Text('重试上次收藏，或选择新的文件？'),
          actions: [
            TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('选择新文件')),
            TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text('重试')),
          ],
        ));
        if (retry == null || isClosed) return;
        if (!retry) {
          _pendingSticker = null;
          pending = null;
        }
      }
      if (pending == null) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'mp4'],
        );
        final file = picked?.files.single;
        if (file?.path == null || isClosed) return;
        final maxSize = file!.extension?.toLowerCase() == 'mp4'
            ? 20 * 1024 * 1024
            : 10 * 1024 * 1024;
        if (file.size > maxSize) {
          IMViews.showToast('文件超过表情收藏上限');
          return;
        }
        final result = await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.uploadFile(
            id: const Uuid().v4(),
            filePath: file.path!,
            fileName: file.name,
          ),
        );
        final data = result is String ? jsonDecode(result) : result;
        final url = data['url'] as String?;
        if (url == null || url.isEmpty) throw StateError('上传未返回文件地址');
        pending = (url: url, requestID: const Uuid().v4());
        _pendingSticker = pending;
      }
      await personalStickers.add(pending.url, pending.requestID);
      _pendingSticker = null;
    } on StickerApiException catch (error) {
      if ([1001, 20012, 20021, 20022, 20023].contains(error.code)) {
        _pendingSticker = null;
      }
      IMViews.showToast('收藏失败：$error');
    } catch (error) {
      IMViews.showToast('收藏失败：$error');
    }
  }

  Future<void> sendPersonalSticker(PersonalSticker sticker) async {
    if (isClosed || sendingMuted || isInvalidGroup) return;
    if (!sticker.isVideo) {
      final message = await OpenIM.iMManager.messageManager
          .createFaceMessage(index: -1, data: sticker.mediaURL);
      if (!isClosed) await _sendMessage(message);
      return;
    }
    final directory = Directory('${Config.cachePath}/outgoing_media');
    await directory.create(recursive: true);
    final prefix = const Uuid().v4();
    final video = File('${directory.path}/$prefix.mp4');
    final cover = File('${directory.path}/$prefix.jpg');
    await dio.download(sticker.mediaURL, video.path);
    await dio.download(sticker.thumbnailURL!, cover.path);
    if (isClosed) return;
    final message =
        await OpenIM.iMManager.messageManager.createVideoMessageFromFullPath(
      videoPath: video.path,
      videoType: sticker.mimeType,
      duration: ((sticker.durationMs ?? 1000) / 1000).ceil(),
      snapshotPath: cover.path,
    );
    markStickerVideoMessage(message);
    await _sendMessage(message);
  }

  Future<void> sendRecordedVoice(String path, int seconds) async {
    if (isClosed || sendingMuted || isInvalidGroup) return;
    try {
      final message = await OpenIM.iMManager.messageManager
          .createSoundMessageFromFullPath(soundPath: path, duration: seconds);
      await _sendMessage(message);
    } catch (_) {
      IMViews.showToast(StrRes.sendFailed);
    }
  }

  Future<void> onTapAudio() => _pickAttachment(true);
  Future<void> _pickAttachment(bool isAudio) async {
    if (_pickingAttachment) return;
    _pickingAttachment = true;
    try {
      final result = await FilePicker.platform
          .pickFiles(type: isAudio ? FileType.audio : FileType.any);
      if (result == null || isClosed) return;
      final selected = result.files.single;
      if (selected.path == null) throw StateError('File unavailable');
      final file = await _retainAttachment(selected.path!);
      Message message;
      if (isAudio) {
        final player = audio.AudioPlayer();
        try {
          final duration = await player.setFilePath(file.path);
          if (duration == null || duration.inMilliseconds <= 0)
            throw StateError('Invalid audio');
          message = await OpenIM.iMManager.messageManager
              .createSoundMessageFromFullPath(
                  soundPath: file.path,
                  duration: (duration.inMilliseconds / 1000).ceil());
        } finally {
          await player.dispose();
        }
      } else {
        message = await OpenIM.iMManager.messageManager
            .createFileMessageFromFullPath(
                filePath: file.path, fileName: selected.name);
      }
      if (!isClosed) await _sendMessage(message);
    } catch (_) {
      IMViews.showToast(StrRes.sendFailed);
    } finally {
      _pickingAttachment = false;
    }
  }

  Future<bool> allowSendImageType(AssetEntity entity) async {
    final mimeType = await entity.mimeTypeAsync;

    return IMUtils.allowImageType(mimeType);
  }

  Future _handleAssets(AssetEntity? asset, {bool sendNow = true}) async {
    if (null != asset) {
      Logger.print(
          '--------assets type-----${asset.type} create time: ${asset.createDateTime}');
      final originalFile = await asset.file;
      if (originalFile == null) {
        IMViews.showToast(StrRes.sendFailed);
        return;
      }
      final originalPath = originalFile.path;
      var path = originalPath.toLowerCase().endsWith('.gif')
          ? originalPath
          : originalFile.path;
      Logger.print('--------assets path-----$path');
      switch (asset.type) {
        case AssetType.image:
          await sendPicture(path: path, sendNow: sendNow);
          break;
        case AssetType.video:
          final saved = await _retainAttachment(path);
          final thumbnail =
              await asset.thumbnailDataWithSize(const ThumbnailSize(640, 640));
          if (thumbnail == null)
            throw StateError('Video thumbnail unavailable');
          final snapshot = File('${saved.path}.jpg');
          await snapshot.writeAsBytes(thumbnail);
          final message = await OpenIM.iMManager.messageManager
              .createVideoMessageFromFullPath(
                  videoPath: saved.path,
                  videoType: await asset.mimeTypeAsync ?? 'video/mp4',
                  duration: asset.videoDuration.inSeconds < 1
                      ? 1
                      : asset.videoDuration.inSeconds,
                  snapshotPath: snapshot.path);
          if (sendNow) {
            await _sendMessage(message);
          } else {
            messageList.add(message);
            tempMessages.add(message);
          }
          break;
        default:
          break;
      }
    }
  }

  void onTapDirectionalMessage() async {
    if (null != groupInfo) {
      final list = await AppNavigator.startGroupMemberList(
        groupInfo: groupInfo!,
        opType: GroupMemberOpType.call,
      );
      if (list is List<GroupMembersInfo>) {
        directionalUsers.assignAll(list);
      }
    }
  }

  TextSpan? directionalText() {
    if (directionalUsers.isNotEmpty) {
      final temp = <TextSpan>[];

      for (var e in directionalUsers) {
        final r = TextSpan(
          text: '${e.nickname ?? ''} ${directionalUsers.last == e ? '' : ','} ',
          style: Styles.ts_0089FF_14sp,
        );

        temp.add(r);
      }

      return TextSpan(
        text: '${StrRes.directedTo}:',
        style: Styles.ts_8E9AB0_14sp,
        children: temp,
      );
    }

    return null;
  }

  void onClearDirectional() {
    directionalUsers.clear();
  }

  void parseClickEvent(Message msg) async {
    log('parseClickEvent:${jsonEncode(msg)}');
    if (msg.contentType == MessageType.custom) {
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
        viewUserInfo(userInfo, isCard: msg.isCardType);
      },
    );
  }

  void onTapLeftAvatar(Message message) {
    viewUserInfo(UserInfo()
      ..userID = message.sendID
      ..nickname = message.senderNickname
      ..faceURL = message.senderFaceUrl);
  }

  void onTapRightAvatar() {
    viewUserInfo(OpenIM.iMManager.userInfo);
  }

  void viewUserInfo(UserInfo userInfo, {bool isCard = false}) {
    if (isGroupChat && !isAdminOrOwner && !isCard) {
      if (groupInfo!.lookMemberInfo != 1) {
        AppNavigator.startUserProfilePane(
          userID: userInfo.userID!,
          nickname: userInfo.nickname,
          faceURL: userInfo.faceURL,
          groupID: groupID,
          offAllWhenDelFriend: isSingleChat,
        );
      }
    } else {
      AppNavigator.startUserProfilePane(
        userID: userInfo.userID!,
        nickname: userInfo.nickname,
        faceURL: userInfo.faceURL,
        groupID: groupID,
        offAllWhenDelFriend: isSingleChat,
        forceCanAdd: isCard,
      );
    }
  }

  void clickLinkText(url, type) async {
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  Future<void> searchMentionID(String id) async {
    final candidates = mentionIDCandidates(id.trim());
    if (candidates.first.isEmpty) return;
    final results = await LoadingView.singleton.wrap(asyncFunction: () async {
      final usersFuture = _findMentionUsers(candidates);
      final groupsFuture = _findMentionGroups(candidates);
      return (await usersFuture, await groupsFuture);
    });
    if (isClosed) return;

    final user =
        results.$1.firstWhereOrNull((item) => candidates.contains(item.userID));
    final group = results.$2
        .firstWhereOrNull((item) => candidates.contains(item.groupID));
    if (group != null) {
      AppNavigator.startGroupProfilePanel(
        groupID: group.groupID,
        joinGroupMethod: JoinGroupMethod.search,
      );
    } else if (user != null) {
      AppNavigator.startUserProfilePane(
        userID: user.userID!,
        nickname: user.nickname,
        faceURL: user.faceURL,
      );
    } else {
      IMViews.showToast('mentionIdNotFound'.tr);
    }
  }

  Future<List<UserFullInfo>> _findMentionUsers(List<String> candidates) async {
    for (final candidate in candidates) {
      try {
        final users = await Apis.searchUserFullInfo(content: candidate);
        final exact =
            users?.where((item) => candidates.contains(item.userID)).toList();
        if (exact != null && exact.isNotEmpty) return exact;
      } catch (_) {}
    }
    return [];
  }

  Future<List<GroupInfo>> _findMentionGroups(List<String> candidates) async {
    for (final candidate in candidates) {
      try {
        final groups = await OpenIM.iMManager.groupManager
            .getGroupsInfo(groupIDList: [candidate]);
        if (groups.any((item) => candidates.contains(item.groupID))) {
          return groups;
        }
      } catch (_) {}
    }
    for (final candidate in candidates) {
      try {
        final groups = await OpenIM.iMManager.groupManager
            .searchGroups(keywordList: [candidate], isSearchGroupID: true);
        if (groups.any((item) => candidates.contains(item.groupID))) {
          return groups;
        }
      } catch (_) {}
    }
    return [];
  }

  exit() async {
    Get.back();

    return true;
  }

  void focusNodeChanged(bool hasFocus) {
    if (hasFocus) {
      Logger.print('focus:$hasFocus');
      scrollBottom();
    }
  }

  Message indexOfMessage(int index, {bool calculate = true}) =>
      IMUtils.calChatTimeInterval(
        messageList,
        calculate: calculate,
      ).reversed.elementAt(index);

  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);

  @override
  void onClose() {
    voicePlayback.dispose();
    personalStickers.dispose();
    _typingExpiry?.cancel();
    _muteExpiry?.cancel();
    for (final subscription in _messageSubscriptions) {
      subscription.cancel();
    }
    _draftTimer?.cancel();
    _saveDraft();
    if (Get.isRegistered<ContactsLogic>()) {
      Get.find<ContactsLogic>().setProfilePresence(this, null);
    }
    sendTypingMsg();
    _clearUnreadCount();
    inputCtrl.dispose();
    focusNode.dispose();
    forceCloseToolbox.close();
    conversationSub.cancel();
    sendStatusSub.close();
    memberAddSub.cancel();
    memberDelSub.cancel();
    memberInfoChangedSub.cancel();
    groupInfoUpdatedSub.cancel();
    friendInfoChangedSub.cancel();
    userStatusChangedSub?.cancel();
    selfInfoUpdatedSub?.cancel();
    joinedGroupAddedSub.cancel();
    joinedGroupDeletedSub.cancel();
    connectionSub.cancel();

    _debounce?.cancel();
    super.onClose();
  }

  String? getShowTime(Message message) {
    if (message.exMap['showTime'] == true) {
      return IMUtils.getChatTimeline(message.sendTime!);
    }
    return null;
  }

  void clearAllMessage() {
    messageList.clear();
  }

  Future<void> deleteMessage(Message message) async {
    final clientMsgID = message.clientMsgID;
    if (clientMsgID == null) return;
    try {
      await OpenIM.iMManager.messageManager.deleteMessageFromLocalStorage(
        conversationID: conversationInfo.conversationID,
        clientMsgID: clientMsgID,
      );
      _removeMessageByID(clientMsgID);
      copyTextMap.remove(clientMsgID);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  void _initChatConfig() async {
    scaleFactor.value = DataSp.getChatFontSizeFactor();
    var path = DataSp.getChatBackground(otherId) ?? '';
    if (path.isNotEmpty && (await File(path).exists())) {
      background.value = path;
    }
  }

  String get otherId => isSingleChat ? userID! : groupID!;

  void failedResend(Message message) {
    Logger.print('failedResend: ${message.clientMsgID}');
    if (message.status == MessageStatus.sending) {
      return;
    }
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: true,
    ));

    Logger.print('failedResending: ${message.clientMsgID}');
    _sendMessage(message..status = MessageStatus.sending, addToUI: false);
  }

  static int get _timestamp => DateTime.now().millisecondsSinceEpoch;

  void destroyMsg() {
    for (var message in privateMessageList) {
      OpenIM.iMManager.messageManager.deleteMessageFromLocalAndSvr(
        conversationID: conversationInfo.conversationID,
        clientMsgID: message.clientMsgID!,
      );
    }
  }

  Future _queryMyGroupMemberInfo() async {
    if (!isGroupChat) {
      return;
    }
    var list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
      groupID: groupID!,
      userIDList: [OpenIM.iMManager.userID],
    );
    groupMembersInfo = list.firstOrNull;
    _refreshMute();
    groupMemberRoleLevel.value =
        groupMembersInfo?.roleLevel ?? GroupRoleLevel.member;
    if (null != groupMembersInfo) {
      memberUpdateInfoMap[OpenIM.iMManager.userID] = groupMembersInfo!;
    }

    return;
  }

  Future _queryOwnerAndAdmin() async {
    if (isGroupChat) {
      ownerAndAdmin = await OpenIM.iMManager.groupManager
          .getGroupMemberList(groupID: groupID!, filter: 5, count: 20);
    }
    return;
  }

  void _isJoinedGroup() async {
    if (!isGroupChat) {
      return;
    }
    isInGroup.value = await OpenIM.iMManager.groupManager.isJoinedGroup(
      groupID: groupID!,
    );
    if (!isInGroup.value) {
      return;
    }
    _queryGroupInfo();
    _queryOwnerAndAdmin();
  }

  void _queryGroupInfo() async {
    if (!isGroupChat) {
      return;
    }
    var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [groupID!],
    );
    groupInfo = list.firstOrNull;
    announcement.value = groupInfo?.notification ?? '';
    announcementVersion.value =
        groupInfo?.notificationUpdateTime?.toString() ?? '';
    _refreshMute();
    groupOwnerID = groupInfo?.ownerUserID;
    if (null != groupInfo?.memberCount) {
      memberCount.value = groupInfo!.memberCount!;
    }
    _queryMyGroupMemberInfo();
  }

  bool get havePermissionMute =>
      isGroupChat &&
      (groupInfo?.ownerUserID ==
          OpenIM.iMManager
              .userID /*||
          groupMembersInfo?.roleLevel == 2*/
      );

  bool isNotificationType(Message message) => message.contentType! >= 1000;

  Map<String, String> getAtMapping(Message message) {
    return IMUtils.getAtMapping(message, {
      for (final entry in memberUpdateInfoMap.entries)
        if (entry.value.nickname != null) entry.key: entry.value.nickname!,
    });
  }

  void _checkInBlacklist() async {
    if (userID != null) {
      var list = await OpenIM.iMManager.friendshipManager.getBlacklist();
      var user = list.firstWhereOrNull((e) => e.userID == userID);
      isInBlacklist.value = user != null;
    }
  }

  bool isExceed24H(Message message) {
    int milliseconds = message.sendTime!;
    return !DateUtil.isToday(milliseconds);
  }

  String? getNewestNickname(Message message) {
    if (isSingleChat) null;

    return message.senderNickname;
  }

  String? getNewestFaceURL(Message message) {
    return message.senderFaceUrl;
  }

  bool get isInvalidGroup => !isInGroup.value && isGroupChat;

  void _resetGroupAtType() {
    if (conversationInfo.groupAtType != GroupAtType.atNormal) {
      OpenIM.iMManager.conversationManager.resetConversationGroupAtType(
        conversationID: conversationInfo.conversationID,
      );
    }
  }

  WillPopCallback? willPop() {
    return null;
  }

  void call() {
    if (rtcIsBusy) {
      IMViews.showToast(StrRes.callingBusy);
      return;
    }

    IMViews.openIMCallSheet(nickname.value, (index) {
      imLogic.call(
        callObj: CallObj.single,
        callType: index == 0 ? CallType.audio : CallType.video,
        inviteeUserIDList: [if (isSingleChat) userID!],
      );
    });
  }

  void callDirectly(CallType type) {
    if (rtcIsBusy) {
      IMViews.showToast(StrRes.callingBusy);
      return;
    }
    if (!isSingleChat) return;
    imLogic.call(
      callObj: CallObj.single,
      callType: type,
      inviteeUserIDList: [userID!],
    );
  }

  void callAudio() => callDirectly(CallType.audio);

  void callVideo() => callDirectly(CallType.video);

  void onScrollToTop() {
    if (scrollingCacheMessageList.isNotEmpty) {
      messageList.addAll(scrollingCacheMessageList);
      scrollingCacheMessageList.clear();
    }
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

  bool isFailedHintMessage(Message message) {
    if (message.contentType == MessageType.custom) {
      var data = message.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      return customType == CustomMessageType.deletedByFriend ||
          customType == CustomMessageType.blockedByFriend;
    }
    return false;
  }

  void sendFriendVerification() =>
      AppNavigator.startSendVerificationApplication(userID: userID);

  void _setSdkSyncDataListener() {
    connectionSub = imLogic.imSdkStatusPublishSubject.listen((value) {
      syncStatus.value = value.status;
      if (value.status == IMSdkStatus.syncStart) {
        _isStartSyncing = true;
      } else if (value.status == IMSdkStatus.syncEnded) {
        if (/*_isReceivedMessageWhenSyncing &&*/ _isStartSyncing) {
          _isReceivedMessageWhenSyncing = false;
          _isStartSyncing = false;
          _isFirstLoad = true;
          _loadHistoryForSyncEnd();
        }
      } else if (value.status == IMSdkStatus.syncFailed) {
        _isReceivedMessageWhenSyncing = false;
        _isStartSyncing = false;
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

  bool showBubbleBg(Message message) {
    return !isNotificationType(message) && !isFailedHintMessage(message);
  }

  Future<AdvancedMessage> _fetchHistoryMessages() {
    Logger.print(
        '_fetchHistoryMessages: is first load: $_isFirstLoad, last client id: ${_isFirstLoad ? null : messageList.firstOrNull?.clientMsgID}');
    return OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
      conversationID: conversationInfo.conversationID,
      count: _pageSize,
      startMsg: _isFirstLoad ? null : messageList.firstOrNull,
    );
  }

  Future<bool> onScrollToBottomLoad() async {
    late List<Message> list;
    final result = await _fetchHistoryMessages();
    if (result.messageList == null || result.messageList!.isEmpty) {
      _getGroupInfoAfterLoadMessage();

      return false;
    }
    list = result.messageList!;
    if (_isFirstLoad) {
      _isFirstLoad = false;
      // remove the message that has been timed down
      messageList.assignAll(
          list.where((m) => !_removedMessageIDs.contains(m.clientMsgID)));
      scrollBottom();

      _getGroupInfoAfterLoadMessage();
    } else {
      messageList.insertAll(
          0, list.where((m) => !_removedMessageIDs.contains(m.clientMsgID)));
    }

    return result.isEnd != true;
  }

  Future<void> _loadHistoryForSyncEnd() async {
    final result =
        await OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
      conversationID: conversationInfo.conversationID,
      count: messageList.length < _pageSize ? _pageSize : messageList.length,
      startMsg: null,
    );
    if (result.messageList == null) return;
    final list = result.messageList!;

    if (isClosed) return;
    final offset = scrollController.hasClients ? scrollController.offset : 0.0;
    messageList.assignAll(
        list.where((m) => !_removedMessageIDs.contains(m.clientMsgID)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && scrollController.hasClients)
        scrollController.jumpTo(
            offset.clamp(0.0, scrollController.position.maxScrollExtent));
    });
  }

  void _getGroupInfoAfterLoadMessage() {
    if (isGroupChat && ownerAndAdmin.isEmpty) {
      _isJoinedGroup();
    } else {
      _checkInBlacklist();
    }
  }

  recommendFriendCarte(UserInfo userInfo) async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.recommend,
      ex: '[${StrRes.carte}]${userInfo.nickname}',
    );
    if (null != result) {
      final customEx = result['customEx'];
      final checkedList = result['checkedList'];
      for (var info in checkedList) {
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);
        if (customEx is String && customEx.isNotEmpty) {
          _sendMessage(
            await OpenIM.iMManager.messageManager.createTextMessage(
              text: customEx,
            ),
            userId: userID,
            groupId: groupID,
          );
        }
        _sendMessage(
          await OpenIM.iMManager.messageManager.createCardMessage(
            userID: userInfo.userID!,
            nickname: userInfo.nickname!,
            faceURL: userInfo.faceURL,
          ),
          userId: userID,
          groupId: groupID,
        );
      }
    }
  }

  @override
  void onDetached() {}

  @override
  void onHidden() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {
    _saveDraft();
  }

  @override
  void onResumed() {
    _loadHistoryForSyncEnd();
  }
}
