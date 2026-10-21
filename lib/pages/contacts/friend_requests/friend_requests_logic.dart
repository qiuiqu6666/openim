import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../core/im_callback.dart';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../home/home_logic.dart';
import '../request_history/data/request_history_store.dart';
import '../request_history/data/request_list_cache.dart';
import '../request_history/data/request_load_coordinator.dart';
import '../request_history/navigation/request_history_chat_opener.dart';

class FriendRequestsLogic extends GetxController with WidgetsBindingObserver {
  final imLogic = Get.find<IMController>();
  final homeLogic = Get.find<HomeLogic>();
  final applicationList = <FriendApplicationInfo>[].obs;
  final loading = true.obs;
  final loadFailed = false.obs;
  final cleaning = false.obs;
  final editing = false.obs;
  final selected = <String>{}.obs;
  final _chatOpener = RequestHistoryChatOpener();
  final _ownerAccount = OpenIM.iMManager.userID;
  final _ownerToken = DataSp.chatToken;
  late final _history =
      RequestHistoryStore(_ownerAccount, RequestHistoryKind.friend);
  int _loadVersion = 0;
  final _loads = RequestLoadCoordinator();
  late StreamSubscription faSub;
  StreamSubscription? _syncSub;

  bool get isSessionActive =>
      !isClosed &&
      _ownerAccount == OpenIM.iMManager.userID &&
      _ownerToken == DataSp.chatToken;

  bool _visible(FriendApplicationInfo info) =>
      !_history.isHidden(RequestHistoryEntry.friend(info));

  Future<void> deleteRequest(FriendApplicationInfo info) =>
      _clean(() => _history.hide(RequestHistoryEntry.friend(info)));

  Future<void> clearRequests() => _clean(
      () => _history.clear(applicationList.map(RequestHistoryEntry.friend)));

  String selectionKey(FriendApplicationInfo info) =>
      RequestHistoryEntry.friend(info).id;

  bool get allSelected =>
      applicationList.isNotEmpty &&
      applicationList.every((item) => selected.contains(selectionKey(item)));

  void toggleEditing() {
    if (!isSessionActive || cleaning.value) return;
    editing.toggle();
    selected.clear();
  }

  void toggleSelection(FriendApplicationInfo info) {
    if (!isSessionActive || cleaning.value) return;
    final key = selectionKey(info);
    if (!selected.remove(key)) selected.add(key);
  }

  void toggleAll() {
    if (!isSessionActive || cleaning.value) return;
    if (allSelected) {
      selected.clear();
    } else {
      selected.addAll(applicationList.map(selectionKey));
    }
  }

  Future<void> deleteSelected() async {
    if (selected.isEmpty) return;
    final entries = applicationList
        .where((item) => selected.contains(selectionKey(item)))
        .map(RequestHistoryEntry.friend)
        .toList();
    await _clean(() => _history.hideAll(entries));
    if (isSessionActive && selected.isEmpty) editing.value = false;
  }

  void _retainSelection() {
    final visible = applicationList.map(selectionKey).toSet();
    selected.removeWhere((key) => !visible.contains(key));
  }

  Future<void> openChat(FriendApplicationInfo info) => _chatOpener.open(
      sourceID: isISendRequest(info) ? info.toUserID : info.fromUserID,
      sessionType: ConversationType.single,
      isCurrent: () => isSessionActive);

  Future<void> _clean(Future<void> Function() save) async {
    if (!isSessionActive || cleaning.value) return;
    cleaning.value = true;
    try {
      await save();
      if (!isSessionActive) return;
      applicationList.removeWhere((item) => !_visible(item));
      _retainSelection();
      _cacheRows();
      homeLogic.getUnhandledFriendApplicationCount();
    } catch (_) {
      if (isSessionActive) IMViews.showToast('requestHistoryCleanupFailed'.tr);
    } finally {
      if (!isClosed) cleaning.value = false;
    }
  }

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    _syncSub = imLogic.imSdkStatusPublishSubject.listen((event) {
      if (event.status == IMSdkStatus.syncEnded && isSessionActive) {
        unawaited(loadRequests(refreshAfter: true));
      }
    });
    applicationList.assignAll(RequestListCache.shared
        .read(_ownerAccount, _ownerToken, RequestHistoryKind.friend,
            FriendApplicationInfo.fromJson)
        .where(_visible));
    faSub = imLogic.friendApplicationChangedSubject.listen((value) {
      loadRequests(refreshAfter: true);
    });
    super.onInit();
    unawaited(loadRequests());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncSub?.cancel();
    _loads.close();
    _loadVersion++;
    faSub.cancel();
    homeLogic.getUnhandledFriendApplicationCount();
    super.onClose();
  }

  Future<void> loadRequests({bool refreshAfter = false}) {
    if (refreshAfter && _loads.busy) _loadVersion++;
    return _loads.run(_loadRequests, refreshAfter: refreshAfter);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isSessionActive) {
      unawaited(loadRequests(refreshAfter: true));
    }
  }

  void _cacheRows() {
    if (!isSessionActive) return;
    RequestListCache.shared.save(_ownerAccount, _ownerToken,
        RequestHistoryKind.friend, applicationList.map((row) => row.toJson()));
  }

  Future<void> _loadRequests() async {
    if (!isSessionActive) return;
    final watch = Stopwatch()..start();
    final version = ++_loadVersion;
    loading.value = true;
    loadFailed.value = false;
    try {
      final showPartial = applicationList.isEmpty;
      final partial = <FriendApplicationInfo>[];
      List<FriendApplicationInfo> preview(List<FriendApplicationInfo> rows) {
        if (showPartial && isSessionActive && version == _loadVersion) {
          partial.addAll(rows);
          partial
              .sort((a, b) => (b.createTime ?? 0).compareTo(a.createTime ?? 0));
          final seen = <String>{};
          applicationList.assignAll(partial.where((row) =>
              _visible(row) && seen.add(RequestHistoryEntry.friend(row).id)));
        }
        return rows;
      }

      final list = await Future.wait([
        OpenIM.iMManager.friendshipManager
            .getFriendApplicationListAsRecipient()
            .then((rows) {
          Logger.print(
              '[FriendRequests][recipient] elapsedMs=${watch.elapsedMilliseconds} rows=${rows.length}',
              onlyConsole: true);
          return preview(rows);
        }),
        OpenIM.iMManager.friendshipManager
            .getFriendApplicationListAsApplicant()
            .then((rows) {
          Logger.print(
              '[FriendRequests][applicant] elapsedMs=${watch.elapsedMilliseconds} rows=${rows.length}',
              onlyConsole: true);
          // Outgoing rows belong below incoming rows. Publishing them first
          // would move the visible list when the recipient read completes.
          return rows;
        }),
      ]);
      if (!isSessionActive || version != _loadVersion) return;

      final allList = <FriendApplicationInfo>[];
      allList
        ..addAll(list[0])
        ..addAll(list[1]);

      allList.sort((a, b) => (b.createTime ?? 0).compareTo(a.createTime ?? 0));

      final haveReadList =
          DataSp.getHaveReadUnHandleFriendApplication()?.toSet() ?? <String>{};
      for (var e in list[0]) {
        var id = IMUtils.buildFriendApplicationID(e);
        if (!haveReadList.contains(id)) {
          haveReadList.add(id);
        }
      }
      DataSp.putHaveReadUnHandleFriendApplication(haveReadList.toList());
      final seen = <String>{};
      applicationList.assignAll(allList.where((item) =>
          _visible(item) && seen.add(RequestHistoryEntry.friend(item).id)));
      _retainSelection();
      _cacheRows();
    } catch (_) {
      if (isSessionActive && version == _loadVersion) loadFailed.value = true;
    } finally {
      if (isSessionActive && version == _loadVersion) loading.value = false;
      Logger.print(
          '[FriendRequests][load] elapsedMs=${watch.elapsedMilliseconds} '
          'rows=${applicationList.length} failed=${loadFailed.value}',
          onlyConsole: true);
    }
  }

  bool isISendRequest(FriendApplicationInfo info) =>
      info.fromUserID == OpenIM.iMManager.userID;

  void acceptFriendApplication(FriendApplicationInfo info) async {
    if (!isSessionActive || isISendRequest(info) || !info.isWaitingHandle) {
      return;
    }
    final result =
        await AppNavigator.startProcessFriendRequests(applicationInfo: info);
    if (isSessionActive && result is int) {
      info.handleResult = result;
      applicationList.refresh();
      _cacheRows();
    }
  }

  void refuseFriendApplication(FriendApplicationInfo info) async {}
}
