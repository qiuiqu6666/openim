import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import '../../../core/controller/im_controller.dart';
import '../../../core/im_callback.dart';
import '../../../routes/app_navigator.dart';
import '../../home/home_logic.dart';
import '../request_history/data/request_load_coordinator.dart';
import '../request_history/navigation/request_history_chat_opener.dart';
import 'data/group_notices_api.dart';

class GroupRequestsLogic extends GetxController with WidgetsBindingObserver {
  GroupRequestsLogic(
      {GroupNoticesApi? api, this.syncInterval = const Duration(seconds: 15)})
      : api = api ??
            (Get.isRegistered<GroupNoticesApi>()
                ? Get.find<GroupNoticesApi>()
                : GroupNoticesApi());
  final GroupNoticesApi api;
  final Duration syncInterval;
  final imLogic = Get.find<IMController>();
  final homeLogic = Get.find<HomeLogic>();
  final _chatOpener = RequestHistoryChatOpener();
  final list = <GroupApplicationInfo>[].obs;
  final applicationsLoaded = false.obs;
  final applicationsLoadFailed = false.obs;
  final hasMore = true.obs;
  final loadingMore = false.obs;
  final cleaning = false.obs;
  final refreshController = RefreshController();
  final groupList = <String, GroupInfo>{}.obs;
  final memberList = <GroupMembersInfo>[].obs;
  final userInfoList = <UserInfo>[].obs;
  final _handlerNames = <String, String>{}.obs;
  final _inviterNames = <String, String>{}.obs;
  final _loads = RequestLoadCoordinator();
  GroupApplicationInfo? _reviewRequest;
  final _reviewDetail = Rxn<GroupApplicationInfo>();
  void trackReview(GroupApplicationInfo info) {
    _reviewRequest = info;
    _reviewDetail.value = info;
  }

  void endReview() {
    _reviewRequest = null;
    _reviewDetail.value = null;
  }

  GroupApplicationInfo? findApplication(GroupApplicationInfo info) =>
      list.firstWhereOrNull((r) => _key(r) == _key(info)) ??
      (_reviewDetail.value != null && _key(_reviewDetail.value!) == _key(info)
          ? _reviewDetail.value
          : null);
  StreamSubscription<GroupApplicationInfo>? _subscription;
  StreamSubscription? _syncSubscription;
  Timer? _poll;
  String _cursor = '';
  int _snapshot = 0, _revision = -1, _generation = 0;
  bool _foreground = true, _checking = false;
  bool get isSessionActive => !isClosed && api.isCurrent;
  String _key(GroupApplicationInfo r) =>
      '${r.groupID}/${r.userID}/${r.reqTime}';

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _syncSubscription = imLogic.imSdkStatusPublishSubject.listen((event) {
      if (event.status == IMSdkStatus.syncEnded && isSessionActive) {
        unawaited(reloadApplications());
      }
    });
    _subscription = imLogic.groupApplicationChangedSubject
        .listen((_) => reloadApplications());
    if (syncInterval > Duration.zero) {
      _poll = Timer.periodic(syncInterval, (_) => _checkRemote());
    }
    unawaited(reloadApplications());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(reloadApplications());
  }

  Future<void> _checkRemote() async {
    if (!_foreground ||
        !isSessionActive ||
        _checking ||
        _loads.busy ||
        cleaning.value) {
      return;
    }
    _checking = true;
    try {
      final state = await api.state(unread: false);
      if (isSessionActive && state['revision'] != _revision) {
        await reloadApplications();
      }
    } catch (_) {
      // Keep the current page; the next foreground check retries synchronization.
    } finally {
      _checking = false;
    }
  }

  @override
  void onClose() {
    ++_generation;
    _poll?.cancel();
    _subscription?.cancel();
    _syncSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _loads.close();
    api.close();
    refreshController.dispose();
    homeLogic.getUnhandledGroupApplicationCount();
    super.onClose();
  }

  Future<void> reloadApplications() async {
    try {
      await getApplicationList();
    } catch (e) {
      Logger.print('Group notice lookup failed: ${e.runtimeType}');
    }
  }

  Future<void> loadMore() async {
    if (_loads.busy ||
        !hasMore.value ||
        !applicationsLoaded.value ||
        cleaning.value) {
      return;
    }
    try {
      await getApplicationList(loadMore: true);
    } catch (_) {}
  }

  Future<void> getApplicationList({bool loadMore = false}) {
    if (!loadMore) ++_generation;
    return _loads.run(() => _load(loadMore), refreshAfter: !loadMore);
  }

  Future<void> _load(bool more) async {
    if (!isSessionActive) return;
    final generation = _generation;
    bool current() => isSessionActive && generation == _generation;
    loadingMore.value = more;
    if (!more) applicationsLoaded.value = false;
    applicationsLoadFailed.value = false;
    try {
      var page = await api.list(cursor: more ? _cursor : '');
      if (!current()) return;
      // A clear/delete on another device invalidates the old page cursor.
      if (page.reset) {
        more = false;
        page = await api.list();
      }
      if (!current()) return;
      if (page.reset) throw StateError('Notice snapshot changed');
      final reviewed = _reviewRequest;
      Map<String, dynamic>? detail;
      if (!more &&
          reviewed != null &&
          !page.items.any((r) => _key(r) == _key(reviewed))) {
        try {
          detail = await api.detail(reviewed);
        } catch (_) {/* A detail outage must not discard the loaded list. */}
        if (!current()) return;
      }
      if (!more) {
        final retained = reviewed == null ? null : _key(reviewed);
        _handlerNames.removeWhere((key, _) => key != retained);
        _inviterNames.removeWhere((key, _) => key != retained);
        list.assignAll(page.items);
      } else {
        final seen = list.map(_key).toSet();
        list.addAll(page.items.where((r) => seen.add(_key(r))));
      }
      final detailCurrent = detail != null &&
          reviewed != null &&
          _reviewRequest != null &&
          _key(_reviewRequest!) == _key(reviewed);
      if (detailCurrent) {
        _reviewDetail.value = GroupApplicationInfo.fromJson(detail);
      }
      for (final raw in [...page.raw, if (detailCurrent) detail]) {
        final row = GroupApplicationInfo.fromJson(raw);
        _handlerNames[_key(row)] = raw['handlerNickname'] as String? ?? '';
        _inviterNames[_key(row)] = raw['inviterNickname'] as String? ?? '';
      }
      _cursor = page.cursor;
      _snapshot = page.snapshot;
      _revision = page.revision;
      hasMore.value = _cursor.isNotEmpty;
      applicationsLoaded.value = true;
      if (!more) refreshController.refreshCompleted(resetFooterState: true);
      if (hasMore.value) {
        refreshController.loadComplete();
      } else {
        refreshController.loadNoData();
      }
      if (!more && _snapshot > 0) unawaited(_markRead(_snapshot));
    } catch (_) {
      if (!current()) return;
      if (current()) {
        if (more) {
          refreshController.loadFailed();
        } else {
          applicationsLoadFailed.value = true;
          refreshController.refreshFailed();
        }
      }
      rethrow;
    } finally {
      if (!isClosed) loadingMore.value = false;
    }
  }

  Future<void> _markRead(int snapshot) async {
    try {
      await api.read(snapshot);
      if (isSessionActive) homeLogic.getUnhandledGroupApplicationCount();
    } catch (_) {/* Read acknowledgement retries on next successful refresh. */}
  }

  Future<void> deleteRequest(GroupApplicationInfo info) =>
      _clean(() => api.delete(info), (r) => _key(r) == _key(info));
  Future<void> clearRequests() {
    final through = _snapshot;
    return _clean(() => api.clear(through), (r) {
      final time = r.reqTime ?? 0;
      return (time < 100000000000 ? time * 1000 : time) <= through;
    });
  }

  Future<void> _clean(Future<void> Function() save,
      bool Function(GroupApplicationInfo) hidden) async {
    if (!isSessionActive || cleaning.value) return;
    cleaning.value = true;
    try {
      await save();
      if (!isSessionActive) return;
      ++_generation;
      list.removeWhere(hidden);
      // Invalidate an older in-flight list before publishing fresh visibility.
      // A successful write stays reflected even if the follow-up read fails.
      await reloadApplications();
      if (isSessionActive) homeLogic.getUnhandledGroupApplicationCount();
    } catch (_) {
      if (isSessionActive) IMViews.showToast('requestHistoryCleanupFailed'.tr);
    } finally {
      if (!isClosed) cleaning.value = false;
    }
  }

  bool isInvite(GroupApplicationInfo r) =>
      r.joinSource == 2 && (r.inviterUserID?.isNotEmpty ?? false);
  String getGroupName(GroupApplicationInfo r) => r.groupName ?? '';
  String? getGroupAvatar(GroupApplicationInfo r) => r.groupFaceURL;
  String getInviterNickname(GroupApplicationInfo r) =>
      _inviterNames[_key(r)]?.isNotEmpty == true
          ? _inviterNames[_key(r)]!
          : '-';
  String? getHandlerNickname(GroupApplicationInfo r) {
    if (r.handleResult != 1 && r.handleResult != -1) return null;
    return IMUtils.emptyStrToNull(_handlerNames[_key(r)]?.trim());
  }

  GroupMembersInfo? getMemberInfo(String id) =>
      memberList.firstWhereOrNull((e) => e.userID == id);
  UserInfo? getUserInfo(String id) =>
      userInfoList.firstWhereOrNull((e) => e.userID == id);
  Future<void> openChat(GroupApplicationInfo r) => _chatOpener.open(
      sourceID: r.groupID,
      sessionType: ConversationType.superGroup,
      isCurrent: () => isSessionActive);
  void handle(GroupApplicationInfo info) async {
    if (!isSessionActive) return;
    await AppNavigator.startProcessGroupRequests(applicationInfo: info);
    if (isSessionActive) await reloadApplications();
  }
}
