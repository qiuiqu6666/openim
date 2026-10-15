import 'updates/conversation_update_buffer.dart';
import 'updates/conversation_row_equality.dart';
import 'editing/batch_read/conversation_batch_read_api.dart';
import 'editing/batch_read/conversation_batch_read_runner.dart';
import 'editing/batch_read/conversation_batch_read_projection.dart';
import 'updates/conversation_latest_sync.dart';
import 'updates/conversation_snapshot_reader.dart';
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
import '../../core/conversation_reads/conversation_read_recovery.dart';
import '../../routes/app_navigator.dart';
import '../../services/legacy_identity/legacy_group_identity.dart';
import '../../services/chat_history_cache.dart';
import '../chat/navigation/chat_entry_trace.dart';
import '../contacts/add_by_search/add_by_search_logic.dart';
import '../home/home_logic.dart';
import '../group_features/data/group_feature_runtime.dart';
import 'conversation_organizer.dart';
import 'deletion/conversation_deletion_guard.dart';
import 'drafts/conversation_draft_text.dart';
import 'legacy_cleanup/legacy_service_conversation_cleanup.dart';
import 'group_identity/legacy_group_conversation_projection.dart';
import 'summary/conversation_latest_message_text.dart';
import 'summary/conversation_incremental_order.dart';
import 'summary/conversation_feed_snapshot.dart';
import 'settings/conversation_settings_projection.dart';
import 'unread/conversation_unread_count.dart';
import 'unread/conversation_unread_sync.dart';

class ConversationLogic extends GetxController with WidgetsBindingObserver {
  ConversationLogic({LegacyServiceConversationCleanup? legacyCleanup})
      : _legacyCleanup = legacyCleanup ?? LegacyServiceConversationCleanup();

  static const int _receiveMessages = 0;
  static const int _receiveWithoutNotification = 2;
  final popCtrl = CustomPopupMenuController();
  final list = <ConversationInfo>[].obs;
  final folders = <ChatFolder>[].obs;
  final states = <String, ChatConversationState>{}.obs;
  ConversationFeedSnapshotCache? _feedCache;
  ConversationFeedSnapshot get feedSnapshot =>
      (_feedCache ??= ConversationFeedSnapshotCache(list, states)).read();
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
  final _snapshots = ConversationSnapshotReader();
  Future<void>? _listRequest;
  bool _listFirstPageOnly = false;
  bool _fullReadQueued = false;
  int _structureRevision = 0;
  final _snapshotSortState = <String, (bool, int)>{};
  bool _reconcileUnreadPending = false;
  final _listLoading = false.obs;
  final _listFailed = false.obs;
  bool get canShowEmptyFeed => !_listLoading.value && !_listFailed.value;
  final _changesDuringRead = <String, ConversationInfo?>{};
  final _deletions = ConversationDeletionGuard();
  final _readProjection = ConversationReadProjection();
  final _settingsDuringRead = ConversationSettingsProjection();
  final _groupProjection = LegacyGroupConversationProjection();
  final LegacyServiceConversationCleanup _legacyCleanup;
  Future<void>? _legacyMutation;
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
    delay: () => const Duration(milliseconds: 80),
  );
  late final _unreadSync = ConversationUnreadSync(
    isActive: () => _sessionActive,
    isReading: () => _readingList,
    flushChanges: _updates.flush,
    localUnreadCount: () => sumSdkConversationUnread(list),
    reload: () =>
        _loadConversationList(firstPageOnly: false, reconcileUnread: true),
    onError: (error, _) =>
        Logger.print('Conversation unread reconciliation failed: $error'),
  );

  void queueChanges(List<ConversationInfo> changes) {
    if (!_sessionActive) return;
    if (_readingList) {
      for (final info in changes) {
        final previous = _snapshotSortState[info.conversationID];
        final next = (info.isPinned == true, info.latestMsgSendTime ?? 0);
        if (previous != null &&
            ((previous.$1 && !next.$1) || next.$2 < previous.$2)) {
          ++_structureRevision;
        }
        _snapshotSortState[info.conversationID] = next;
      }
    }
    _latestSync
        .conversationsChanged(changes.map((info) => info.conversationID));
    if (_readingList) {
      for (final info in changes) {
        if (_deletions.allows(info)) {
          _changesDuringRead[info.conversationID] = info;
        }
      }
    }
    _latestSync.conversationsUpdated(changes);
    _updates.add(changes);
  }

  late final _latestSync = ConversationLatestSync(
    isActive: () => _sessionActive,
    flushChanges: _updates.flush,
    // The query excludes rows changed while it was in flight. Its current SDK
    // zero can therefore reconcile a count outside an older read projection.
    publish: (rows) => onChanged(rows, authoritativeUnread: true),
  );

  @override
  void onInit() {
    getFirstPage();
    WidgetsBinding.instance.addObserver(this);
    _businessSubscription = imLogic.customBusinessMessageSubject
        .listen(_handleBusinessNotification);
    refreshOrganizer();
    _subscriptions.add(imLogic.conversationAddedSubject.listen(queueChanges));
    _subscriptions.add(imLogic.conversationChangedSubject.listen(queueChanges));
    _subscriptions
        .add(imLogic.receivedMessages.listen(_latestSync.observeMessage));
    _subscriptions.add(
        ConversationRefreshEvents.changes.listen(_latestSync.requestRefresh));
    _subscriptions.add(imLogic.unreadMsgCountEventSubject
        .listen(_unreadSync.onTotalUnreadChanged));
    _subscriptions.add(imLogic.conversationReadRequestSubject
        .listen(onConversationReadRequested));
    void handleSdkStatus(
        ({IMSdkStatus status, bool reInstall, int? progress}) value) {
      if (!_sessionActive) return;
      final status = value.status;
      final previousStatus = imStatus.value;
      final appReInstall = value.reInstall;
      final progress = value.progress;
      imStatus.value = status;

      if (status == IMSdkStatus.connectionSucceeded) {
        refreshOrganizer();
        if (previousStatus != IMSdkStatus.connectionSucceeded &&
            !_listFailed.value) {
          _unreadSync.reconcile();
        }
        _retryFailedList();
      }

      if (status == IMSdkStatus.syncStart) {
        if (reInstall && !appReInstall) EasyLoading.dismiss();
        reInstall = appReInstall;
        if (reInstall) {
          EasyLoading.showProgress(0, status: StrRes.synchronizing);
        }
      }
      if (status == IMSdkStatus.syncProgress && appReInstall) reInstall = true;
      if (status == IMSdkStatus.syncProgress && reInstall && progress != null) {
        final percent = progress.clamp(0, 100);
        EasyLoading.showProgress(percent / 100.0,
            status: '${StrRes.synchronizing}($percent%)');
      }

      Logger.print(
          'IM SDK Status: $status, reinstall: $reInstall, progress: $progress');

      if (status == IMSdkStatus.syncEnded || status == IMSdkStatus.syncFailed) {
        _updates.flush();
        if (reInstall) EasyLoading.dismiss();
        // A normal login also needs a snapshot after sync: the first local
        // read may have been empty or failed before the SDK became ready.
        // Ignore repeated finish callbacks so a query cannot start a read loop.
        if (reInstall ||
            (status == IMSdkStatus.syncEnded &&
                previousStatus != IMSdkStatus.syncEnded)) {
          unawaited(_refreshConversations(
              afterCurrentRead: status == IMSdkStatus.syncEnded));
        }
        reInstall = false;
      }
    }

    _subscriptions.add(imLogic.imSdkStatusSubject.listen(handleSdkStatus));
    final initialSync = imLogic.initialSyncState;
    if (initialSync != null) handleSdkStatus(initialSync);
    super.onInit();
  }

  @override
  void onClose() {
    _serverBatchReads?.close();
    if (reInstall) EasyLoading.dismiss();
    _feedCache?.dispose();
    _feedCache = null;
    _closed = true;
    _reconcileUnreadPending = false;
    _unreadSync.close();
    _latestSync.close();
    _snapshots.close();
    _snapshotSortState.clear();
    _fullReadQueued = false;
    _updates.close();
    ++_listGeneration;
    ++_clearGeneration;
    _changesDuringRead.clear();
    _deletions.clear();
    _readProjection.clear();
    _groupProjection.clear();
    _settingsDuringRead.clear();
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
    if (_sessionActive && state == AppLifecycleState.resumed) {
      refreshOrganizer();
      groupFeatures.refreshKnownGroups();
      if (_listFailed.value) {
        _retryFailedList();
      } else {
        _unreadSync.reconcile();
      }
    }
  }

  void _retryFailedList() {
    if (_sessionActive && _listFailed.value && !_readingList) {
      unawaited(onRefresh());
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

  void onChanged(List<ConversationInfo> newList,
      {bool authoritativeUnread = false}) {
    if (!_sessionActive || newList.isEmpty) return;
    _latestSync
        .conversationsChanged(newList.map((info) => info.conversationID));
    final accepted = <ConversationInfo>[];
    final currentByID = {
      for (final info in list) info.conversationID: info,
    };
    for (final info in newList) {
      if (!_deletions.allows(info)) continue;
      final projected = _readProjection.project(
          _settingsDuringRead.project(info),
          current: currentByID[info.conversationID],
          authoritativeUnread: authoritativeUnread);
      accepted.add(projected);
      if (!authoritativeUnread &&
          _readProjection.takeReconciliationSignal(info, projected)) {
        // A protected zero is a reconciliation signal even when the aggregate
        // total hasn't changed. Never turn the callback itself into authority.
        _refreshReadConversation(info.conversationID);
      }
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
    // Preserve read fences and reconciliation above even for duplicate rows.
    final changedIDs = <String>{};
    for (final info in accepted) {
      if (sameConversationData(currentByID[info.conversationID], info))
        continue;
      currentByID[info.conversationID] = info;
      changedIDs.add(info.conversationID);
    }
    if (changedIDs.isEmpty) return;
    final merged = _groupProjection.project(currentByID.values);
    list.value = mergeConversationOrder(list, merged, changedIDs);
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

  final _pendingMarkReads = <String, Future<void>>{};
  Future<void> markConversationRead(ConversationInfo info) async {
    if (!_sessionActive) throw StateError('Session is no longer active');
    if (info.unreadCount == 0) return;
    final request = ConversationReadRequest.capture(info);
    final projecting = onConversationReadRequested(request);
    try {
      final id = info.conversationID;
      final pending = _pendingMarkReads.putIfAbsent(id, () {
        final native = OpenIM.iMManager.conversationManager
            .markConversationMessageAsRead(conversationID: id)
            .then<void>((_) {});
        unawaited(native.then<void>((_) => _pendingMarkReads.remove(id),
            onError: (Object _, StackTrace __) {
          _pendingMarkReads.remove(id);
        }));
        return native;
      });
      await pending.timeout(const Duration(seconds: 10));
      request.complete(true);
      await projecting;
    } catch (_) {
      request.complete(false);
      await projecting;
      rethrow;
    }
  }

  final markingAllRead = false.obs;
  final readBatchProgress = ''.obs;
  ConversationBatchReadApi? _serverBatchReads;

  Future<void> markReadScope(bool Function(ConversationInfo) includes) =>
      _markServerReadScope(includes: includes);

  Future<void> markAllConversationsRead(String scope) =>
      _markServerReadScope(scope: scope);

  Future<void> markSelectedConversationsRead(List<String> ids) =>
      _markServerReadScope(conversationIDs: ids);

  Future<void> _markServerReadScope(
      {String scope = 'selected',
      List<String>? conversationIDs,
      bool Function(ConversationInfo)? includes}) async {
    if (markingAllRead.value || !_sessionActive) return;
    markingAllRead.value = true;
    readBatchProgress.value = '准备中…';
    final generation = _clearGeneration;
    bool current() => _sessionActive && generation == _clearGeneration;
    final reader =
        ConversationSnapshotReader(timeout: const Duration(minutes: 2));
    final api = _serverBatchReads = ConversationBatchReadApi();
    try {
      final rows = includes == null
          ? <ConversationInfo>[]
          : await reader.read(
              firstPageOnly: false,
              isCurrent: current,
              structureRevision: () => _structureRevision,
              observePage: (_) {},
              waitForMutation: _legacyMutation);
      if (!current()) return;
      final projection = ConversationBatchReadProjection(list);
      final failed = await runServerConversationReadBatch(
          scope: scope,
          conversationIDs: conversationIDs ??
              rows
                  .where((row) => includes?.call(row) ?? false)
                  .map((row) => row.conversationID)
                  .toList(),
          prepare: (scope, ids) => api.prepare(scope, conversationIDs: ids),
          apply: api.apply,
          isCurrent: () => current() && api.isCurrent,
          confirmed: (targets) {
            if (projection.confirm(targets, list, _readProjection.confirm)) {
              list.refresh();
            }
          },
          progress: (done, total) =>
              readBatchProgress.value = '$done / $total');
      if (!current()) return;
      await _loadConversationList(firstPageOnly: false, reconcileUnread: true);
      if (current() && failed > 0) {
        IMViews.showToast('$failed 个会话未完成已读，请稍后重试');
      }
    } catch (error) {
      if (current()) IMViews.showErrorToast(error);
    } finally {
      api.close();
      if (identical(_serverBatchReads, api)) _serverBatchReads = null;
      reader.close();
      markingAllRead.value = false;
      readBatchProgress.value = '';
    }
  }

  Future<void> onConversationReadRequested(
      ConversationReadRequest request) async {
    if (!_sessionActive) return;
    final clearing = _clearGeneration;
    final succeeded = await request.result;
    bool current() =>
        _sessionActive && clearing == _clearGeneration && request.isCurrent;
    if (!current()) return;
    if (!succeeded) {
      try {
        await ConversationReadRecovery().recover(request, isCurrent: current);
      } catch (error) {
        Logger.print('Conversation read recovery failed: $error');
      }
      // A partial ID recovery is not a full read confirmation. Ask the SDK for
      // the remaining unread count, including any message received after exit.
      if (current()) _refreshReadConversation(request.conversationID);
      return;
    }
    _readProjection.confirm(request);
    var changed = false;
    for (final info in list) {
      if (request.canClear(info) && info.unreadCount > 0) {
        info.unreadCount = 0;
        changed = true;
      }
    }
    if (changed) list.refresh();
    if (list.any((info) =>
        info.conversationID == request.conversationID &&
        info.unreadCount > 0)) {
      _refreshReadConversation(request.conversationID);
    }
  }

  void _refreshReadConversation(String conversationID) =>
      _latestSync.requestRefresh(ConversationRefreshRequest(
          accountID: _accountID, conversationID: conversationID));

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
      ++_structureRevision;
      _updates.flush();
      _latestSync.conversationsChanged([info.conversationID]);
      info.isPinned = pinned;
      if (_readingList) {
        _settingsDuringRead.pinned(info.conversationID, pinned);
      }
      for (final conversation in list) {
        if (conversation.conversationID == info.conversationID) {
          conversation.isPinned = pinned;
          break;
        }
      }
      _sortConversationList();
      list.refresh();
    } catch (error) {
      if (_sessionActive) IMViews.showErrorToast(error);
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
      _latestSync.conversationsChanged([info.conversationID]);
      info.recvMsgOpt =
          enabled ? _receiveWithoutNotification : _receiveMessages;
      if (_readingList) {
        _settingsDuringRead.receiveOption(
            info.conversationID, info.recvMsgOpt!);
      }
      for (final conversation in list) {
        if (conversation.conversationID == info.conversationID) {
          conversation.recvMsgOpt = info.recvMsgOpt;
          break;
        }
      }
      list.refresh();
    } catch (error) {
      if (_sessionActive) IMViews.showErrorToast(error);
    }
  }

  Future<void> deleteConversation(ConversationInfo info,
      {bool propagateError = false}) async {
    if (!_sessionActive || !_deletions.begin(info)) return;
    ++_structureRevision;
    _latestSync.discard(info);
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
      ++_structureRevision;
      _deletions.complete(info.conversationID);
      if (_readingList) _changesDuringRead[info.conversationID] = null;
      ChatHistoryCache.removeConversation(
          OpenIM.iMManager.userID, info.conversationID);
      list.removeWhere((item) => item.conversationID == info.conversationID);
      tempDraftText.remove(info.conversationID);
    } catch (error) {
      if (_sessionActive && clearing == _clearGeneration) {
        onChanged([_deletions.fail(info.conversationID) ?? info]);
        if (!propagateError) IMViews.showErrorToast(error);
      }
      if (propagateError) rethrow;
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
        return StrRes.connecting;
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

  Future<void> onRefresh() => _refreshConversations();

  Future<void> _refreshConversations({bool afterCurrentRead = false}) async {
    final clearing = _clearGeneration;
    await _loadConversationList(
        firstPageOnly: false, afterCurrentRead: afterCurrentRead);
    if (_sessionActive && clearing == _clearGeneration) {
      unawaited(_cleanupLegacyConversations());
    }
  }

  Future<void> _cleanupLegacyConversations() async {
    if (!_sessionActive || _readingList) return;
    final clearing = _clearGeneration;
    bool active() => _sessionActive && clearing == _clearGeneration;
    void removeLocal(ConversationInfo info) {
      final id = info.conversationID;
      _latestSync.discard(info);
      _updates.remove(id);
      onChangeConversations.remove(id);
      _deletions.begin(info);
      _deletions.complete(id);
      if (_readingList) _changesDuringRead[id] = null;
      ChatHistoryCache.removeConversation(_accountID, id);
      list.removeWhere((item) => item.conversationID == id);
      homeLogic.conversationsAtFirstPage
          .removeWhere((item) => item.conversationID == id);
      tempDraftText.remove(id);
    }

    await _legacyCleanup.run(
      isActive: active,
      onDeleted: removeLocal,
      mutate: (action) => _mutateLegacyConversation(action, active),
    );
  }

  Future<bool> _mutateLegacyConversation(
      Future<void> Function() action, bool Function() active) async {
    if (!active() || _readingList) return false;
    final task = Future<void>.sync(action);
    _legacyMutation = task;
    try {
      await task;
      return true;
    } finally {
      if (identical(_legacyMutation, task)) _legacyMutation = null;
    }
  }

  Future<void> _loadConversationList(
      {required bool firstPageOnly,
      bool useCachedFirstPage = false,
      bool reconcileUnread = false,
      bool afterCurrentRead = false}) {
    if (!_sessionActive) return Future.value();
    if (reconcileUnread) _reconcileUnreadPending = true;
    final pending = _listRequest;
    if (pending != null) {
      // Sync may finish after a full read took its local snapshot. Preserve
      // one trailing read even when the in-flight request is already full.
      if (!firstPageOnly && (_listFirstPageOnly || afterCurrentRead)) {
        _fullReadQueued = true;
      }
      return pending;
    }
    final completer = Completer<void>();
    final clearing = _clearGeneration;
    _listRequest = completer.future;
    _listFirstPageOnly = firstPageOnly;
    void finish() {
      if (identical(_listRequest, completer.future)) {
        _listRequest = null;
        _fullReadQueued = false;
        _listFirstPageOnly = false;
      }
    }

    unawaited(Future<void>.sync(() async {
      await _readConversationSnapshot(
          firstPageOnly: firstPageOnly, useCachedFirstPage: useCachedFirstPage);
      while (
          _fullReadQueued && _sessionActive && clearing == _clearGeneration) {
        _fullReadQueued = false;
        _listFirstPageOnly = false;
        await _readConversationSnapshot(firstPageOnly: false);
      }
    }).then<void>((_) {
      finish();
      completer.complete();
    }, onError: (Object error, StackTrace stack) {
      finish();
      completer.completeError(error, stack);
    }));
    return completer.future;
  }

  Future<void> _readConversationSnapshot(
      {required bool firstPageOnly, bool useCachedFirstPage = false}) async {
    if (!_sessionActive) return;
    final generation = ++_listGeneration;
    _readingList = true;
    _listLoading.value = true;
    _listFailed.value = false;
    _changesDuringRead.clear();
    _settingsDuringRead.clear();
    _snapshotSortState.clear();
    for (final info in list) {
      _snapshotSortState[info.conversationID] =
          (info.isPinned == true, info.latestMsgSendTime ?? 0);
    }
    try {
      // Only an already-started local mutation may delay a list read. History
      // checks run in the background and cannot shift SDK pagination offsets.
      if (!_sessionActive || generation != _listGeneration) return;
      final cached = firstPageOnly && useCachedFirstPage
          ? homeLogic.conversationsAtFirstPage
          : const <ConversationInfo>[];
      final usesCachedSnapshot =
          firstPageOnly && useCachedFirstPage && cached.isNotEmpty;
      final snapshot = usesCachedSnapshot
          ? List<ConversationInfo>.of(cached)
          : await _snapshots.read(
              firstPageOnly: firstPageOnly,
              isCurrent: () => _sessionActive && generation == _listGeneration,
              structureRevision: () => _structureRevision,
              waitForMutation: _legacyMutation,
              observePage: (rows) {
                for (final info in rows) {
                  _snapshotSortState.putIfAbsent(
                      info.conversationID,
                      () =>
                          (info.isPinned == true, info.latestMsgSendTime ?? 0));
                }
              });
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
      final merged = _groupProjection
          .project(byID.values)
          .map((info) => _readProjection.project(
              _settingsDuringRead.project(info),
              current: currentByID[info.conversationID],
              authoritativeUnread: _reconcileUnreadPending &&
                  !usesCachedSnapshot &&
                  !_changesDuringRead.containsKey(info.conversationID)))
          .toList();
      OpenIM.iMManager.conversationManager.simpleSort(merged);
      _latestSync
          .conversationsChanged(merged.map((info) => info.conversationID));
      list.value = merged;
      if (!firstPageOnly) onChangeConversations.clear();
      if (_reconcileUnreadPending && !usesCachedSnapshot) {
        _reconcileUnreadPending = false;
        _unreadSync.snapshotReconciled(
            hadChanges: _changesDuringRead.isNotEmpty);
      }

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
        _settingsDuringRead.clear();
        _snapshotSortState.clear();
        _unreadSync.snapshotFinished();
        if (_sessionActive) {
          _listLoading.value = false;
          if (_listFailed.value) {
            refreshController.refreshFailed();
          } else {
            refreshController.refreshCompleted();
          }
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
    final clearing = _clearGeneration;
    await _loadConversationList(firstPageOnly: true, useCachedFirstPage: true);
    // Publish local rows before maintenance scans/history/network checks. The
    // deletion guard still rejects stale SDK snapshots after cleanup finishes.
    if (_sessionActive && clearing == _clearGeneration) {
      unawaited(_cleanupLegacyConversations());
    }
  }

  void clearConversations() {
    _serverBatchReads?.close();
    _reconcileUnreadPending = false;
    _unreadSync.reset();
    _latestSync.reset();
    _updates.clear();
    onChangeConversations.clear();
    ChatHistoryCache.clear();
    ++_listGeneration;
    ++_clearGeneration;
    ++_structureRevision;
    _listRequest = null;
    _fullReadQueued = false;
    _snapshotSortState.clear();
    _readingList = false;
    _listLoading.value = false;
    _listFailed.value = false;
    _changesDuringRead.clear();
    _deletions.clear();
    _readProjection.clear();
    _groupProjection.clear();
    _settingsDuringRead.clear();
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
        IMViews.showErrorToast(error);
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
      if (_sessionActive) IMViews.showErrorToast(error);
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
      if (_sessionActive) IMViews.showErrorToast(error);
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
      if (_sessionActive) IMViews.showErrorToast(error);
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
      if (_sessionActive) IMViews.showErrorToast(error);
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
        IMViews.showErrorToast(error);
        await refreshOrganizer();
      }
      return false;
    } finally {
      _reorderingFolders = false;
    }
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
    final entryTrace = ChatEntryTrace(conversationInfo?.conversationType ?? sessionType);
    if (groupID != null) groupID = LegacyGroupIdentity.canonical(groupID);
    conversationInfo ??= await _createConversation(
      sourceID: userID ?? groupID!,
      sessionType: userID == null ? sessionType! : ConversationType.single,
    );

    if (await _jumpOANtf(conversationInfo)) return;

    await AppNavigator.startChat(
      entryTrace: entryTrace,
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
