import 'updates/conversation_update_buffer.dart';
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
import '../../core/conversation_reads/conversation_read_projection.dart';
import '../../core/conversation_reads/conversation_read_request.dart';
import '../../routes/app_navigator.dart';
import '../../services/chat_history_cache.dart';
import '../contacts/add_by_search/add_by_search_logic.dart';
import '../home/home_logic.dart';
import '../group_features/data/group_feature_runtime.dart';
import 'conversation_organizer.dart';
import 'deletion/conversation_deletion_guard.dart';
import 'drafts/conversation_draft_text.dart';
import 'summary/conversation_latest_message_text.dart';

class ConversationLogic extends GetxController with WidgetsBindingObserver {
  static const int _receiveMessages = 0;
  static const int _receiveWithoutNotification = 2;
  final popCtrl = CustomPopupMenuController();
  final list = <ConversationInfo>[].obs;
  final folders = <ChatFolder>[].obs;
  final states = <String, ChatConversationState>{}.obs;
  final organizerLoading = false.obs;
  final organizerError = RxnString();
  int _organizerSyncAt = 0;
  bool _refreshPending = false;
  bool _reorderingFolders = false;
  StreamSubscription<String>? _businessSubscription;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _closed = false;
  final _accountID = OpenIM.iMManager.userID;
  final _accountToken = DataSp.chatToken;
  int _listGeneration = 0;
  int _clearGeneration = 0;
  bool _readingList = false;
  final _listLoading = false.obs;
  final _listFailed = false.obs;
  bool get canShowEmptyFeed => !_listLoading.value && !_listFailed.value;
  final _changesDuringRead = <String, ConversationInfo?>{};
  final _deletions = ConversationDeletionGuard();
  final _readProjection = ConversationReadProjection();
  bool get _sessionActive =>
      !_closed &&
      _accountID == OpenIM.iMManager.userID &&
      _accountToken == DataSp.chatToken;
  bool get isSessionActive => _sessionActive;
  final imLogic = Get.find<IMController>();
  late final GroupFeatureStore groupFeatures =
      GroupFeatureRuntime.forAccount(imLogic);
  final homeLogic = Get.find<HomeLogic>();
  final appLogic = Get.find<AppController>();
  final refreshController = RefreshController();
  final tempDraftText = <String, String>{};
  final pageSize = 400;

  final imStatus = IMSdkStatus.connectionSucceeded.obs;
  bool reInstall = false;

  final onChangeConversations = <String, ConversationInfo>{};
  late final _updates = ConversationUpdateBuffer(
    publish: onChanged,
    delay: () => Duration(
        milliseconds: imStatus.value == IMSdkStatus.syncStart ||
                imStatus.value == IMSdkStatus.syncProgress
            ? 80
            : 16),
  );

  void queueChanges(List<ConversationInfo> changes) {
    if (!_sessionActive) return;
    if (_readingList) {
      for (final info in changes) {
        if (_deletions.allows(info)) {
          _changesDuringRead[info.conversationID] = info;
        }
      }
    }
    _updates.add(changes);
  }

  @override
  void onInit() {
    getFirstPage();
    WidgetsBinding.instance.addObserver(this);
    _businessSubscription = imLogic.customBusinessMessageSubject
        .listen(_handleBusinessNotification);
    refreshOrganizer();
    _subscriptions.add(imLogic.conversationAddedSubject.listen(queueChanges));
    _subscriptions.add(imLogic.conversationChangedSubject.listen(queueChanges));
    _subscriptions.add(imLogic.conversationReadRequestSubject
        .listen(onConversationReadRequested));
    _subscriptions.add(imLogic.imSdkStatusSubject.listen((value) {
      if (_closed) return;
      final status = value.status;
      final appReInstall = value.reInstall;
      final progress = value.progress;
      imStatus.value = status;

      if (status == IMSdkStatus.connectionSucceeded) {
        refreshOrganizer();
      }

      if (status == IMSdkStatus.syncStart ||
          status == IMSdkStatus.syncProgress) {
        if (status == IMSdkStatus.syncStart) reInstall = appReInstall;
        if (status == IMSdkStatus.syncStart && reInstall) {
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
        _updates.flush();
        EasyLoading.dismiss();
        if (reInstall) {
          onRefresh();
          reInstall = false;
        }
      }
    }));
    super.onInit();
  }

  @override
  void onClose() {
    _closed = true;
    _updates.close();
    ++_listGeneration;
    ++_clearGeneration;
    _changesDuringRead.clear();
    _deletions.clear();
    _readProjection.clear();
    WidgetsBinding.instance.removeObserver(this);
    _businessSubscription?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    refreshController.dispose();
    popCtrl.dispose();
    list.clear();
    folders.clear();
    states.clear();
    onChangeConversations.clear();
    reInstall = false;
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshOrganizer();
      groupFeatures.refreshKnownGroups();
    }
  }

  void _handleBusinessNotification(String raw) {
    if (!_sessionActive) return;
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

  void _upsertFolder(ChatFolder folder, {ChatFolder? expected}) {
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (index < 0) {
      folders.add(folder);
    } else if (folder.updatedAt > folders[index].updatedAt ||
        (folder.updatedAt == folders[index].updatedAt &&
            identical(folders[index], expected))) {
      folders[index] = folder;
    }
    _sortFolders();
  }

  void _sortFolders() {
    folders.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.createdAt.compareTo(b.createdAt);
    });
  }

  void onChanged(List<ConversationInfo> newList) {
    if (!_sessionActive || newList.isEmpty) return;
    final accepted = <ConversationInfo>[];
    final currentByID = {
      for (final info in list) info.conversationID: info,
    };
    for (final info in newList) {
      if (!_deletions.allows(info)) continue;
      accepted.add(_readProjection.project(info,
          current: currentByID[info.conversationID]));
    }
    if (accepted.isEmpty) return;
    if (_readingList) {
      for (final info in accepted) {
        _changesDuringRead[info.conversationID] = info;
      }
    }
    if (reInstall) {
      for (final info in accepted) {
        onChangeConversations[info.conversationID] = info;
      }
    }
    for (final info in accepted) {
      currentByID[info.conversationID] = info;
    }
    final merged = currentByID.values.toList();
    OpenIM.iMManager.conversationManager.simpleSort(merged);
    list.value = merged;
    groupFeatures.hydrate(
        accepted.where((info) => info.isGroupChat).map((info) => info.groupID));
  }

  String getConversationID(ConversationInfo info) {
    return info.conversationID;
  }

  String? getPrefixTag(ConversationInfo info) => conversationPrefixTag(info);

  String getContent(ConversationInfo info) {
    try {
      final draft = conversationDraftText(info.draftText);
      if (draft != null) return draft;

      return conversationLatestMessageText(info);
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

  Future<void> markConversationRead(ConversationInfo info) async {
    if (!_sessionActive) throw StateError('Session is no longer active');
    if (info.unreadCount == 0) return;
    final request = ConversationReadRequest.capture(info);
    final projecting = onConversationReadRequested(request);
    try {
      await OpenIM.iMManager.conversationManager
          .markConversationMessageAsRead(conversationID: info.conversationID);
      request.complete(true);
      await projecting;
    } catch (_) {
      request.complete(false);
      await projecting;
      rethrow;
    }
  }

  Future<void> onConversationReadRequested(
      ConversationReadRequest request) async {
    if (!_sessionActive) return;
    final clearing = _clearGeneration;
    final succeeded = await request.result;
    if (!succeeded || !_sessionActive || clearing != _clearGeneration) return;
    _readProjection.confirm(request);
    var changed = false;
    for (final info in list) {
      if (request.canClear(info) && info.unreadCount > 0) {
        info.unreadCount = 0;
        changed = true;
      }
    }
    if (changed) list.refresh();
  }

  bool isNotDisturb(ConversationInfo info) =>
      info.recvMsgOpt == _receiveWithoutNotification;

  Future<void> setPinned(ConversationInfo info, bool pinned) async {
    if (!_sessionActive) return;
    try {
      await OpenIM.iMManager.conversationManager.setConversation(
        info.conversationID,
        ConversationReq(isPinned: pinned),
      );
      if (!_sessionActive) return;
      _updates.flush();
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
      if (_sessionActive) IMViews.showToast(error.toString());
    }
  }

  Future<void> setNotDisturb(ConversationInfo info, bool enabled) async {
    if (!_sessionActive) return;
    try {
      await OpenIM.iMManager.conversationManager.setConversation(
        info.conversationID,
        ConversationReq(
            recvMsgOpt:
                enabled ? _receiveWithoutNotification : _receiveMessages),
      );
      if (!_sessionActive) return;
      _updates.flush();
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
      if (_sessionActive) IMViews.showToast(error.toString());
    }
  }

  Future<void> deleteConversation(ConversationInfo info) async {
    if (!_sessionActive || !_deletions.begin(info)) return;
    _updates.remove(info.conversationID);
    onChangeConversations.remove(info.conversationID);
    final clearing = _clearGeneration;
    if (_readingList) _changesDuringRead[info.conversationID] = null;
    try {
      await OpenIM.iMManager.conversationManager
          .deleteConversationAndDeleteAllMsg(
        conversationID: info.conversationID,
      );
      if (!_sessionActive || clearing != _clearGeneration) return;
      _deletions.complete(info.conversationID);
      if (_readingList) _changesDuringRead[info.conversationID] = null;
      ChatHistoryCache.removeConversation(
          OpenIM.iMManager.userID, info.conversationID);
      list.removeWhere((item) => item.conversationID == info.conversationID);
      tempDraftText.remove(info.conversationID);
    } catch (error) {
      if (_sessionActive && clearing == _clearGeneration) {
        onChanged([_deletions.fail(info.conversationID) ?? info]);
        IMViews.showToast(error.toString());
      }
    } finally {
      if (clearing == _clearGeneration) _deletions.fail(info.conversationID);
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

  Future<void> onRefresh() => _loadConversationList(firstPageOnly: false);

  Future<void> _loadConversationList({required bool firstPageOnly}) async {
    if (!_sessionActive) return;
    final generation = ++_listGeneration;
    _readingList = true;
    _listLoading.value = true;
    _listFailed.value = false;
    _changesDuringRead.clear();
    try {
      final snapshot = firstPageOnly
          ? await getConversationFirstPage()
          : await _request(generation);
      if (!_sessionActive || generation != _listGeneration) return;
      final byID = {
        for (final info in snapshot
            .where((info) => _deletions.allows(info, snapshot: true)))
          info.conversationID: info
      };
      for (final entry in _changesDuringRead.entries) {
        final changed = entry.value;
        if (changed == null) {
          byID.remove(entry.key);
        } else {
          byID[entry.key] = changed;
        }
      }
      final currentByID = {
        for (final info in list) info.conversationID: info,
      };
      final merged = byID.values
          .map((info) => _readProjection.project(info,
              current: currentByID[info.conversationID]))
          .toList();
      OpenIM.iMManager.conversationManager.simpleSort(merged);
      list.value = merged;
      groupFeatures.hydrate(
          merged.where((info) => info.isGroupChat).map((info) => info.groupID));

      if (snapshot.length < pageSize) {
        refreshController.loadNoData();
      } else {
        refreshController.loadComplete();
      }
    } catch (error) {
      if (_sessionActive && generation == _listGeneration) {
        _listFailed.value = true;
        Logger.print('Conversation list refresh failed: $error');
        refreshController.refreshFailed();
      }
    } finally {
      if (generation == _listGeneration) {
        _readingList = false;
        _changesDuringRead.clear();
        if (_sessionActive) {
          _listLoading.value = false;
          refreshController.refreshCompleted();
        }
      }
    }
  }

  static Future<List<ConversationInfo>> getConversationFirstPage() async {
    final result = await OpenIM.iMManager.conversationManager
        .getConversationListSplit(offset: 0, count: 400);

    return result;
  }

  Future<void> getFirstPage() async {
    final result = homeLogic.conversationsAtFirstPage;
    if (result.isNotEmpty) {
      final currentByID = {
        for (final info in list) info.conversationID: info,
      };
      list.value = result
          .map((info) => _readProjection.project(info,
              current: currentByID[info.conversationID]))
          .toList();
      groupFeatures.hydrate(
          result.where((info) => info.isGroupChat).map((info) => info.groupID));
      _sortConversationList();
    } else {
      await _loadConversationList(firstPageOnly: true);
    }
  }

  void clearConversations() {
    _updates.clear();
    onChangeConversations.clear();
    ChatHistoryCache.clear();
    ++_listGeneration;
    ++_clearGeneration;
    _readingList = false;
    _listLoading.value = false;
    _listFailed.value = false;
    _changesDuringRead.clear();
    _deletions.clear();
    _readProjection.clear();
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
    if (!_sessionActive || DataSp.chatToken == null) return;
    if (organizerLoading.value) {
      _refreshPending = true;
      return;
    }
    organizerLoading.value = true;
    organizerError.value = null;
    final foldersBefore = {for (final folder in folders) folder.id: folder};
    try {
      final fetchedFolders = await ChatOrganizerApi.getFolders();
      if (!_sessionActive) return;
      final fetchedStates =
          await ChatOrganizerApi.getStates(updatedAfter: _organizerSyncAt);
      if (!_sessionActive) return;
      // A folder push/PATCH can arrive while folders and states are loading.
      // Keep newer changes and deletions instead of restoring the old snapshot.
      final currentFolders = {for (final folder in folders) folder.id: folder};
      final mergedFolders = {
        for (final folder in fetchedFolders) folder.id: folder,
      };
      for (final folder in currentFolders.values) {
        final fetched = mergedFolders[folder.id];
        final changed = !identical(folder, foldersBefore[folder.id]);
        if ((fetched != null && folder.updatedAt > fetched.updatedAt) ||
            (changed &&
                (fetched == null || folder.updatedAt >= fetched.updatedAt))) {
          mergedFolders[folder.id] = folder;
        }
      }
      for (final id in foldersBefore.keys) {
        if (!currentFolders.containsKey(id)) mergedFolders.remove(id);
      }
      folders.assignAll(mergedFolders.values);
      _sortFolders();
      for (final entry in fetchedStates.states.entries) {
        _applyState(entry.value);
      }
      if (fetchedStates.syncAt > _organizerSyncAt) {
        _organizerSyncAt = fetchedStates.syncAt;
      }
    } catch (error) {
      if (_sessionActive) {
        organizerError.value = error.toString();
        IMViews.showToast(error.toString());
      }
    } finally {
      if (_sessionActive) {
        organizerLoading.value = false;
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(refreshOrganizer());
        }
      }
    }
  }

  Future<bool> updateOrganizer(ConversationInfo info,
      {required String? folderID, required bool archived}) async {
    if (!_sessionActive) return false;
    final old = states[info.conversationID];
    try {
      final state = await ChatOrganizerApi.putState(
        conversationID: info.conversationID,
        folderID: folderID,
        archived: archived,
        version: old?.version ?? 0,
      );
      if (!_sessionActive) return false;
      _applyState(state);
      return true;
    } on ChatOrganizerConflict catch (error) {
      if (!_sessionActive) return false;
      _applyState(error.current);
      IMViews.showToast('此会话已在另一台设备更新，请重试');
    } catch (error) {
      if (_sessionActive) IMViews.showToast(error.toString());
    }
    return false;
  }

  Future<bool> createFolder(String name) async {
    if (!_sessionActive) return false;
    final sortOrder = folders.isEmpty
        ? 0
        : folders
                .map((folder) => folder.sortOrder)
                .reduce((first, second) => first > second ? first : second) +
            1;
    try {
      final created =
          await ChatOrganizerApi.createFolder(name, sortOrder: sortOrder);
      if (!_sessionActive) return false;
      _upsertFolder(created);
      return true;
    } catch (error) {
      if (_sessionActive) IMViews.showToast(error.toString());
      return false;
    }
  }

  Future<bool> renameFolder(ChatFolder folder, String name) async {
    if (!_sessionActive) return false;
    final current = folders.firstWhereOrNull((item) => item.id == folder.id);
    if (current == null) return false;
    try {
      final updated = await ChatOrganizerApi.renameFolder(folder.id, name);
      if (!_sessionActive || !folders.any((item) => item.id == folder.id)) {
        return false;
      }
      _upsertFolder(updated, expected: current);
      return true;
    } catch (error) {
      if (_sessionActive) IMViews.showToast(error.toString());
      return false;
    }
  }

  Future<bool> deleteFolder(ChatFolder folder) async {
    if (!_sessionActive || !folders.any((item) => item.id == folder.id)) {
      return false;
    }
    try {
      await ChatOrganizerApi.deleteFolder(folder.id);
      if (!_sessionActive) return false;
      folders.removeWhere((item) => item.id == folder.id);
      await refreshOrganizer();
      return _sessionActive;
    } catch (error) {
      if (_sessionActive) IMViews.showToast(error.toString());
      return false;
    }
  }

  /// Commits the page's preview only when it exits folder sorting.
  /// Each server response retains its real timestamp and never revives a
  /// folder removed while the request was pending.
  Future<bool> reorderFolders(List<String> orderedIDs) async {
    if (!_sessionActive || _reorderingFolders) return false;
    final seen = <String>{};
    final ids = orderedIDs
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && seen.add(id))
        .toList(growable: false);
    _reorderingFolders = true;
    try {
      var sortOrder = 0;
      for (final id in ids) {
        if (!_sessionActive) return false;
        final current = folders.firstWhereOrNull((folder) => folder.id == id);
        if (current == null) continue;
        final updated =
            await ChatOrganizerApi.setFolderSortOrder(id, sortOrder);
        if (!_sessionActive) return false;
        if (updated.id != id) {
          throw StateError('Server returned a different folder');
        }
        if (!folders.any((folder) => folder.id == id)) continue;
        _upsertFolder(updated, expected: current);
        sortOrder++;
      }
      return true;
    } catch (error) {
      if (_sessionActive) {
        IMViews.showToast(error.toString());
        await refreshOrganizer();
      }
      return false;
    } finally {
      _reorderingFolders = false;
    }
  }

  Future<List<ConversationInfo>> _request(int generation) async {
    final temp = <ConversationInfo>[];

    while (_sessionActive && generation == _listGeneration) {
      var result =
          await OpenIM.iMManager.conversationManager.getConversationListSplit(
        offset: temp.length,
        count: pageSize,
      );
      if (!_sessionActive || generation != _listGeneration) return temp;
      if (onChangeConversations.isNotEmpty) {
        for (int i = 0; i < result.length; i++) {
          final info = result[i];
          result[i] = onChangeConversations[info.conversationID] ?? info;
        }
      }
      temp.addAll(result);

      if (result.length < pageSize) {
        break;
      }
    }
    if (generation == _listGeneration) onChangeConversations.clear();

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
