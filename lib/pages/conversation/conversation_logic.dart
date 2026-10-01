import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../../routes/app_navigator.dart';
import '../contacts/add_by_search/add_by_search_logic.dart';
import '../home/home_logic.dart';
import 'conversation_organizer.dart';

class ConversationLogic extends GetxController with WidgetsBindingObserver {
  static const int _receiveMessages = 0;
  static const int _receiveWithoutNotification = 2;
  final popCtrl = CustomPopupMenuController();
  final list = <ConversationInfo>[].obs;
  final folders = <ChatFolder>[].obs;
  final states = <String, ChatConversationState>{}.obs;
  final organizerLoading = false.obs;
  int _organizerSyncAt = 0;
  bool _refreshPending = false;
  StreamSubscription<String>? _businessSubscription;
  final imLogic = Get.find<IMController>();
  final homeLogic = Get.find<HomeLogic>();
  final appLogic = Get.find<AppController>();
  final refreshController = RefreshController();
  final tempDraftText = <String, String>{};
  final pageSize = 400;

  final imStatus = IMSdkStatus.connectionSucceeded.obs;
  bool reInstall = false;

  final onChangeConversations = <ConversationInfo>[];

  @override
  void onInit() {
    getFirstPage();
    WidgetsBinding.instance.addObserver(this);
    _businessSubscription = imLogic.customBusinessMessageSubject
        .listen(_handleBusinessNotification);
    refreshOrganizer();
    imLogic.conversationAddedSubject.listen(onChanged);
    imLogic.conversationChangedSubject.listen(onChanged);
    imLogic.imSdkStatusSubject.listen((value) async {
      final status = value.status;
      final appReInstall = value.reInstall;
      final progress = value.progress;
      imStatus.value = status;

      if (status == IMSdkStatus.connectionSucceeded) {
        refreshOrganizer();
      }

      if (status == IMSdkStatus.syncStart) {
        reInstall = appReInstall;
        if (reInstall) {
          EasyLoading.showProgress(0, status: StrRes.synchronizing);
        }
      }

      Logger.print(
          'IM SDK Status: $status, reinstall: $reInstall, progress: $progress');

      if (status == IMSdkStatus.syncProgress && reInstall) {
        final p = (progress!).toDouble() / 100.0;

        EasyLoading.showProgress(p,
            status: '${StrRes.synchronizing}(${(p * 100.0).truncate()}%)');
      } else if (status == IMSdkStatus.syncEnded ||
          status == IMSdkStatus.syncFailed) {
        EasyLoading.dismiss();
        if (reInstall) {
          onRefresh();
          reInstall = false;
        }
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _businessSubscription?.cancel();
    list.clear();
    folders.clear();
    states.clear();
    reInstall = false;
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshOrganizer();
  }

  void _handleBusinessNotification(String raw) {
    try {
      final message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final key = message['key'];
      final rawData = message['data'];
      final data = rawData is String
          ? Map<String, dynamic>.from(jsonDecode(rawData) as Map)
          : Map<String, dynamic>.from(rawData as Map);
      if (key == 'conversationStateChanged') {
        final state = ChatConversationState.fromJson(data);
        _applyState(state);
      } else if (key == 'chatFolderChanged') {
        if (data['op'] == 'delete') {
          final id = data['id'] as String;
          folders.removeWhere((folder) => folder.id == id);
          // The server also clears folderID from associated conversations.
          refreshOrganizer();
        } else if (data['op'] == 'upsert') {
          final folder = ChatFolder.fromJson(
              Map<String, dynamic>.from(data['folder'] as Map));
          _upsertFolder(folder);
        }
      }
    } catch (error) {
      Logger.print('Invalid chat organizer notification: $error');
    }
  }

  void _applyState(ChatConversationState state) {
    final old = states[state.conversationID];
    if (old == null || state.version > old.version) {
      states[state.conversationID] = state;
    }
  }

  void _upsertFolder(ChatFolder folder) {
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (index < 0) {
      folders.add(folder);
    } else if (folder.updatedAt > folders[index].updatedAt) {
      folders[index] = folder;
    }
    folders.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.createdAt.compareTo(b.createdAt);
    });
  }

  void onChanged(List<ConversationInfo> newList) {
    if (reInstall) {
      onChangeConversations.addAll(newList);
    }
    for (var newValue in newList) {
      Logger.print(
          '======== conversation changed: ${newValue.toJson()} ========');
      list.removeWhere((e) => e.conversationID == newValue.conversationID);
    }

    if (newList.length > pageSize) {
      final tempList = newList;

      while (true) {
        final temp = tempList.sublist(0, pageSize);
        list.insertAll(0, temp);
        _sortConversationList();

        if (tempList.length <= pageSize) {
          break;
        }

        tempList.removeRange(0, pageSize);
      }
    } else {
      list.insertAll(0, newList);
      _sortConversationList();
      Logger.print(
          '======== conversation sort result: ${list.where((e) => e.unreadCount > 0).toList().map((e) => '${e.showName} [${e.conversationID}]: ${e.unreadCount}')} ========');
    }
  }

  void promptSoundOrNotification(ConversationInfo info) {
    if (imLogic.userInfo.value.globalRecvMsgOpt == 0 &&
        info.recvMsgOpt == 0 &&
        info.unreadCount > 0 &&
        info.latestMsg?.sendID != OpenIM.iMManager.userID) {
      appLogic.promptSoundOrNotification(info.latestMsg!.seq!);
    }
  }

  String getConversationID(ConversationInfo info) {
    return info.conversationID;
  }

  String? getPrefixTag(ConversationInfo info) {
    if (info.draftText?.isNotEmpty == true) return '[${StrRes.draftText}]';
    if (info.groupAtType == GroupAtType.groupNotification) {
      return '[${StrRes.groupAc}]';
    }

    return null;
  }

  String getContent(ConversationInfo info) {
    try {
      if (null != info.draftText && '' != info.draftText) {
        var text = info.draftText!;
        try {
          final map = json.decode(text);
          if (map is Map && map['text'] is String) text = map['text'];
        } catch (_) {}
        if (text.isNotEmpty) {
          return text;
        }
      }

      if (null == info.latestMsg) return "";

      final text = IMUtils.parseNtf(info.latestMsg!, isConversation: true);
      if (text != null) return text;
      if (info.isSingleChat ||
          info.latestMsg!.sendID == OpenIM.iMManager.userID)
        return IMUtils.parseMsg(info.latestMsg!, isConversation: true);

      return "${info.latestMsg!.senderNickname}: ${IMUtils.parseMsg(info.latestMsg!, isConversation: true)} ";
    } catch (e, s) {
      Logger.print('------e:$e s:$s');
    }
    return '[${StrRes.unsupportedMessage}]';
  }

  String? getAvatar(ConversationInfo info) {
    return info.faceURL;
  }

  bool isGroupChat(ConversationInfo info) {
    return info.isGroupChat;
  }

  String getShowName(ConversationInfo info) {
    if (info.showName == null || info.showName.isBlank!) {
      return info.userID!;
    }
    return info.showName!;
  }

  String getTime(ConversationInfo info) {
    return IMUtils.getChatTimeline(info.latestMsgSendTime!);
  }

  int getUnreadCount(ConversationInfo info) {
    return info.unreadCount;
  }

  bool existUnreadMsg(ConversationInfo info) {
    return getUnreadCount(info) > 0;
  }

  bool isNotDisturb(ConversationInfo info) =>
      info.recvMsgOpt == _receiveWithoutNotification;

  Future<void> setPinned(ConversationInfo info, bool pinned) async {
    try {
      await OpenIM.iMManager.conversationManager.setConversation(
        info.conversationID,
        ConversationReq(isPinned: pinned),
      );
      info.isPinned = pinned;
      for (final conversation in list) {
        if (conversation.conversationID == info.conversationID) {
          conversation.isPinned = pinned;
          break;
        }
      }
      _sortConversationList();
      list.refresh();
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> setNotDisturb(ConversationInfo info, bool enabled) async {
    try {
      await OpenIM.iMManager.conversationManager.setConversation(
        info.conversationID,
        ConversationReq(
            recvMsgOpt:
                enabled ? _receiveWithoutNotification : _receiveMessages),
      );
      info.recvMsgOpt =
          enabled ? _receiveWithoutNotification : _receiveMessages;
      for (final conversation in list) {
        if (conversation.conversationID == info.conversationID) {
          conversation.recvMsgOpt = info.recvMsgOpt;
          break;
        }
      }
      list.refresh();
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> deleteConversation(ConversationInfo info) async {
    try {
      await OpenIM.iMManager.conversationManager
          .deleteConversationAndDeleteAllMsg(
        conversationID: info.conversationID,
      );
      list.removeWhere((item) => item.conversationID == info.conversationID);
      tempDraftText.remove(info.conversationID);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  bool isUserGroup(int index) => list.elementAt(index).isGroupChat;

  String? get imSdkStatus {
    switch (imStatus.value) {
      case IMSdkStatus.syncStart:
      case IMSdkStatus.synchronizing:
      case IMSdkStatus.syncProgress:
        return StrRes.synchronizing;
      case IMSdkStatus.syncFailed:
        return StrRes.syncFailed;
      case IMSdkStatus.connecting:
        return StrRes.connecting;
      case IMSdkStatus.connectionFailed:
        return StrRes.connectionFailed;
      case IMSdkStatus.connectionSucceeded:
      case IMSdkStatus.syncEnded:
        return null;
    }
  }

  bool get isFailedSdkStatus =>
      imStatus.value == IMSdkStatus.connectionFailed ||
      imStatus.value == IMSdkStatus.syncFailed;

  void _sortConversationList() =>
      OpenIM.iMManager.conversationManager.simpleSort(list);

  void onRefresh() async {
    late List<ConversationInfo> list;
    try {
      list = await _request();
      this.list.assignAll(list);

      if (list.isEmpty || list.length < pageSize) {
        refreshController.loadNoData();
      } else {
        refreshController.loadComplete();
      }
    } finally {
      refreshController.refreshCompleted();
    }
  }

  static Future<List<ConversationInfo>> getConversationFirstPage() async {
    final result = await OpenIM.iMManager.conversationManager
        .getConversationListSplit(offset: 0, count: 400);

    return result;
  }

  void getFirstPage() async {
    final result = homeLogic.conversationsAtFirstPage;

    list.assignAll(result);
    _sortConversationList();
  }

  void clearConversations() {
    list.clear();
    folders.clear();
    states.clear();
    _organizerSyncAt = 0;
  }

  bool isArchived(ConversationInfo info) =>
      states[info.conversationID]?.archived ?? false;

  String? folderID(ConversationInfo info) =>
      states[info.conversationID]?.folderID;

  Future<void> refreshOrganizer() async {
    if (DataSp.chatToken == null) return;
    if (organizerLoading.value) {
      _refreshPending = true;
      return;
    }
    organizerLoading.value = true;
    try {
      final fetchedFolders = await ChatOrganizerApi.getFolders();
      final fetchedStates =
          await ChatOrganizerApi.getStates(updatedAfter: _organizerSyncAt);
      if (isClosed) return;
      folders.assignAll(fetchedFolders);
      for (final entry in fetchedStates.states.entries) {
        _applyState(entry.value);
      }
      if (fetchedStates.syncAt > _organizerSyncAt) {
        _organizerSyncAt = fetchedStates.syncAt;
      }
    } catch (error) {
      IMViews.showToast(error.toString());
    } finally {
      organizerLoading.value = false;
      if (_refreshPending && !isClosed) {
        _refreshPending = false;
        unawaited(refreshOrganizer());
      }
    }
  }

  Future<bool> updateOrganizer(ConversationInfo info,
      {required String? folderID, required bool archived}) async {
    final old = states[info.conversationID];
    try {
      final state = await ChatOrganizerApi.putState(
        conversationID: info.conversationID,
        folderID: folderID,
        archived: archived,
        version: old?.version ?? 0,
      );
      _applyState(state);
      return true;
    } on ChatOrganizerConflict catch (error) {
      _applyState(error.current);
      IMViews.showToast('此会话已在另一台设备更新，请重试');
    } catch (error) {
      IMViews.showToast(error.toString());
    }
    return false;
  }

  Future<bool> createFolder(String name) async {
    try {
      _upsertFolder(await ChatOrganizerApi.createFolder(name));
      return true;
    } catch (error) {
      IMViews.showToast(error.toString());
      return false;
    }
  }

  Future<bool> renameFolder(ChatFolder folder, String name) async {
    try {
      final updated = await ChatOrganizerApi.renameFolder(folder.id, name);
      _upsertFolder(updated);
      return true;
    } catch (error) {
      IMViews.showToast(error.toString());
      return false;
    }
  }

  Future<bool> deleteFolder(ChatFolder folder) async {
    try {
      await ChatOrganizerApi.deleteFolder(folder.id);
      folders.removeWhere((item) => item.id == folder.id);
      await refreshOrganizer();
      return true;
    } catch (error) {
      IMViews.showToast(error.toString());
      return false;
    }
  }

  _request() async {
    final temp = <ConversationInfo>[];

    while (true) {
      var result =
          await OpenIM.iMManager.conversationManager.getConversationListSplit(
        offset: temp.length,
        count: pageSize,
      );
      if (onChangeConversations.isNotEmpty) {
        final bSet = Set.from(onChangeConversations);

        Logger.print(
            'replace conversation: [${onChangeConversations.length}], $bSet');

        for (int i = 0; i < result.length; i++) {
          final info = result[i];

          if (bSet.contains(info)) {
            result[i] =
                onChangeConversations[onChangeConversations.indexOf(info)];
          }
        }
      }
      temp.addAll(result);

      if (result.length < pageSize) {
        break;
      }
    }
    onChangeConversations.clear();

    return temp;
  }

  bool isValidConversation(ConversationInfo info) {
    return info.isValid;
  }

  static Future<ConversationInfo> _createConversation({
    required String sourceID,
    required int sessionType,
  }) =>
      LoadingView.singleton.wrap(
          asyncFunction: () =>
              OpenIM.iMManager.conversationManager.getOneConversation(
                sourceID: sourceID,
                sessionType: sessionType,
              ));

  Future<bool> _jumpOANtf(ConversationInfo info) async {
    if (info.conversationType == ConversationType.notification) {
      return true;
    }
    return false;
  }

  void toChat({
    bool offUntilHome = true,
    String? userID,
    String? groupID,
    String? nickname,
    String? faceURL,
    int? sessionType,
    ConversationInfo? conversationInfo,
    Message? searchMessage,
  }) async {
    conversationInfo ??= await _createConversation(
      sourceID: userID ?? groupID!,
      sessionType: userID == null ? sessionType! : ConversationType.single,
    );

    if (await _jumpOANtf(conversationInfo)) return;

    await AppNavigator.startChat(
      offUntilHome: offUntilHome,
      draftText: conversationInfo.draftText,
      conversationInfo: conversationInfo,
      searchMessage: searchMessage,
    );

    bool equal(e) => e.conversationID == conversationInfo?.conversationID;

    var groupAtType = list.firstWhereOrNull(equal)?.groupAtType;
    if (groupAtType != GroupAtType.atNormal) {
      OpenIM.iMManager.conversationManager.resetConversationGroupAtType(
        conversationID: conversationInfo.conversationID,
      );
    }
  }

  addFriend() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.user);

  createGroup() => AppNavigator.startCreateGroup(
      defaultCheckedList: [OpenIM.iMManager.userInfo]);

  addGroup() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.group);

  void globalSearch() => AppNavigator.startGlobalSearch();
}
