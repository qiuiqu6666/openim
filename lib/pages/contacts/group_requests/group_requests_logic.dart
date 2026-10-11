import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../../core/controller/im_controller.dart';
import '../../home/home_logic.dart';
import 'pagination/group_application_pager.dart';
import '../request_history/data/request_history_store.dart';
import '../request_history/data/request_list_cache.dart';
import '../request_history/data/request_load_coordinator.dart';
import '../request_history/navigation/request_history_chat_opener.dart';

class GroupRequestsLogic extends GetxController {
  final _chatOpener = RequestHistoryChatOpener();
  final imLogic = Get.find<IMController>();
  final homeLogic = Get.find<HomeLogic>();
  final list = <GroupApplicationInfo>[].obs;
  // An empty list is conclusive only after the latest SDK read succeeds.
  final applicationsLoaded = false.obs;
  final applicationsLoadFailed = false.obs;
  final hasMore = true.obs;
  final loadingMore = false.obs;
  final cleaning = false.obs;
  final refreshController = RefreshController();
  GroupApplicationPager _pager = GroupApplicationPager();
  bool _loading = false;
  final groupList = <String, GroupInfo>{}.obs;
  final memberList = <GroupMembersInfo>[].obs;
  final userInfoList = <UserInfo>[].obs;
  final _ownerAccount = OpenIM.iMManager.userID;
  final _ownerToken = DataSp.chatToken;
  late final _history =
      RequestHistoryStore(_ownerAccount, RequestHistoryKind.group);
  StreamSubscription<GroupApplicationInfo>? _applicationSubscription;
  int _loadGeneration = 0;
  int _profileGeneration = 0;
  final _loads = RequestLoadCoordinator();

  bool get isSessionActive =>
      !isClosed &&
      _ownerAccount == OpenIM.iMManager.userID &&
      _ownerToken == DataSp.chatToken;

  bool _visible(GroupApplicationInfo info) =>
      !_history.isHidden(RequestHistoryEntry.group(info));

  Future<void> deleteRequest(GroupApplicationInfo info) =>
      _clean(() => _history.hide(RequestHistoryEntry.group(info)),
          clearAll: false);

  Future<void> clearRequests() =>
      _clean(() => _history.clear(list.map(RequestHistoryEntry.group)),
          clearAll: true);

  Future<void> _clean(Future<void> Function() save,
      {required bool clearAll}) async {
    if (!isSessionActive || cleaning.value) return;
    cleaning.value = true;
    try {
      await save();
      if (!isSessionActive) return;
      list.removeWhere((item) => !_visible(item));
      _cacheRows();
      if (clearAll) {
        hasMore.value = false;
        refreshController.loadNoData();
      } else if (list.isEmpty && hasMore.value) {
        await reloadApplications();
      }
      if (isSessionActive) homeLogic.getUnhandledGroupApplicationCount();
    } catch (_) {
      if (isSessionActive) IMViews.showToast('requestHistoryCleanupFailed'.tr);
    } finally {
      if (!isClosed) cleaning.value = false;
    }
  }

  @override
  void onInit() {
    list.assignAll(RequestListCache.shared
        .read(_ownerAccount, _ownerToken, RequestHistoryKind.group,
            GroupApplicationInfo.fromJson)
        .where(_visible));
    _applicationSubscription =
        imLogic.groupApplicationChangedSubject.listen((info) {
      reloadApplications();
    });
    super.onInit();
    unawaited(reloadApplications());
    getJoinedGroup();
  }

  @override
  void onClose() {
    if (applicationsLoaded.value) _cacheRows();
    _loads.close();
    _loadGeneration++;
    _applicationSubscription?.cancel();
    refreshController.dispose();
    homeLogic.getUnhandledGroupApplicationCount();
    super.onClose();
  }

  bool isInvite(GroupApplicationInfo info) {
    if (info.joinSource == 2) {
      return info.inviterUserID != null && info.inviterUserID!.isNotEmpty;
    }
    return false;
  }

  /// Page/event entry point; direct callers still receive SDK read failures.
  Future<void> reloadApplications() async {
    try {
      await getApplicationList();
    } catch (error) {
      Logger.print('Group application lookup failed: ${error.runtimeType}');
    }
  }

  Future<void> loadMore() async {
    if (_loading || !hasMore.value || !applicationsLoaded.value) return;
    try {
      await getApplicationList(loadMore: true);
    } catch (_) {
      // The existing refresh footer offers retry; keep the loaded rows.
    }
  }

  Future<void> getApplicationList({bool loadMore = false}) {
    if (!loadMore && _loads.busy) {
      _loadGeneration++;
      _profileGeneration++;
    }
    return _loads.run(() => _loadApplications(loadMore: loadMore),
        refreshAfter: !loadMore);
  }

  void _cacheRows() {
    if (!isSessionActive) return;
    RequestListCache.shared.save(
        _ownerAccount,
        _ownerToken,
        RequestHistoryKind.group,
        list.take(GroupApplicationPager.pageSize).map((row) => row.toJson()));
  }

  Future<void> _loadApplications({bool loadMore = false}) async {
    if (!isSessionActive || (loadMore && (_loading || !hasMore.value))) return;
    final watch = Stopwatch()..start();
    final generation = ++_loadGeneration;
    final profileGeneration =
        loadMore ? _profileGeneration : ++_profileGeneration;
    _loading = true;
    loadingMore.value = loadMore;
    if (!loadMore) applicationsLoaded.value = false;
    applicationsLoadFailed.value = false;
    final candidate = loadMore ? _pager.fork() : GroupApplicationPager();
    final targetCount = loadMore
        ? GroupApplicationPager.pageSize
        : (this.list.length > GroupApplicationPager.pageSize
            ? this.list.length
            : GroupApplicationPager.pageSize);
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    List<GroupApplicationInfo> lastPage = [];
    bool reachedClearBoundary() => lastPage
        .any((item) => _history.isCleared(RequestHistoryEntry.group(item)));
    bool isCurrent() =>
        isSessionActive &&
        generation == _loadGeneration &&
        account == OpenIM.iMManager.userID &&
        token == DataSp.chatToken;
    late final List<GroupApplicationInfo> list;
    try {
      Future<List<GroupApplicationInfo>> fetchApplications() async {
        if (!isCurrent()) return <GroupApplicationInfo>[];
        final allList = <GroupApplicationInfo>[];
        do {
          lastPage = await candidate.nextPage();
          allList.addAll(lastPage.where(_visible));
          if (!isCurrent()) return allList;
        } while (allList.length < targetCount &&
            candidate.hasMore &&
            !reachedClearBoundary());

        if (!isCurrent()) return allList;
        allList.sort((a, b) => (b.reqTime ?? 0).compareTo(a.reqTime ?? 0));

        final haveReadList =
            DataSp.getHaveReadUnHandleGroupApplication()?.toSet() ?? <String>{};
        for (var a in candidate.receivedIn(allList)) {
          var id = IMUtils.buildGroupApplicationID(a);
          if (!haveReadList.contains(id)) {
            haveReadList.add(id);
          }
        }
        DataSp.putHaveReadUnHandleGroupApplication(haveReadList.toList());

        return allList;
      }

      // The list owns its initial/refresh/footer indicators. SDK notifications
      // and post-approval refreshes must not cover the review page with an
      // overlay after the operation has already succeeded.
      list = await fetchApplications();
    } catch (_) {
      if (isCurrent()) {
        if (loadMore) {
          refreshController.loadFailed();
        } else {
          applicationsLoadFailed.value = true;
          refreshController.refreshFailed();
        }
      }
      rethrow;
    } finally {
      if (isCurrent()) {
        _loading = false;
        loadingMore.value = false;
      }
      Logger.print(
          '[GroupRequests][list] elapsedMs=${watch.elapsedMilliseconds} '
          'loadMore=$loadMore failed=${applicationsLoadFailed.value}',
          onlyConsole: true);
    }

    if (isCurrent()) {
      _pager = candidate;
      if (loadMore) {
        this.list.addAll(list.where(_visible));
      } else {
        this.list.assignAll(list.where(_visible));
        refreshController.refreshCompleted(resetFooterState: true);
      }
      applicationsLoaded.value = true;
      _cacheRows();
      hasMore.value = candidate.hasMore && !reachedClearBoundary();
      if (hasMore.value) {
        refreshController.loadComplete();
      } else {
        refreshController.loadNoData();
      }
      unawaited(_loadProfiles(
          list,
          () => isSessionActive && profileGeneration == _profileGeneration,
          generation));
    }
  }

  Future<void> _loadProfiles(List<GroupApplicationInfo> allList,
      bool Function() isCurrent, int generation) async {
    final watch = Stopwatch()..start();
    final map = <String, List<String>>{};
    final profileIDs = <String>{};
    var profileLookup = 'not_needed';
    for (var a in allList) {
      final handlerID = _handlerUserID(a);
      if (handlerID != null) profileIDs.add(handlerID);
      if (isInvite(a) && IMUtils.isNotNullEmptyStr(a.groupID)) {
        if (!map.containsKey(a.groupID)) {
          map[a.groupID!] = [a.inviterUserID!];
        } else {
          if (!map[a.groupID!]!.contains(a.inviterUserID!)) {
            map[a.groupID!]!.add(a.inviterUserID!);
          }
        }
        profileIDs.add(a.inviterUserID!);
      }
    }

    Future<void> loadMembers() async {
      if (map.isNotEmpty) {
        try {
          final members = await Future.wait(map.entries.map((e) => OpenIM
              .iMManager.groupManager
              .getGroupMembersInfo(groupID: e.key, userIDList: e.value)));
          if (isCurrent()) {
            for (final member in members.expand((group) => group)) {
              memberList.removeWhere((old) =>
                  old.groupID == member.groupID && old.userID == member.userID);
              memberList.add(member);
            }
          }
        } catch (error) {
          Logger.print(
              'Group application member lookup failed: ${error.runtimeType}');
        }
      }
    }

    Future<void> loadUsers() async {
      if (profileIDs.isNotEmpty) {
        try {
          final profiles = await OpenIM.iMManager.userManager
              .getUsersInfo(userIDList: profileIDs.toList());
          profileLookup = 'succeeded';
          if (isCurrent()) {
            for (final profile in profiles.map((e) => e.simpleUserInfo)) {
              userInfoList.removeWhere((old) => old.userID == profile.userID);
              userInfoList.add(profile);
            }
          }
        } catch (error) {
          profileLookup = 'failed';
          // Profile availability must not hide the application's actual result.
          Logger.print(
              'Group application user lookup failed: ${error.runtimeType}');
        }
      }
    }

    await Future.wait([loadMembers(), loadUsers()]);
    if (!isCurrent()) return;
    final processed = allList
        .where((item) => item.handleResult == 1 || item.handleResult == -1);
    final namedIDs = userInfoList
        .where((user) => IMUtils.isNotNullEmptyStr(user.nickname?.trim()))
        .map((user) => user.userID)
        .toSet();
    var missingID = 0;
    var missingNickname = 0;
    var resolved = 0;
    for (final item in processed) {
      final handlerID = _handlerUserID(item);
      if (handlerID == null) {
        missingID++;
      } else if (!namedIDs.contains(handlerID)) {
        missingNickname++;
      } else {
        resolved++;
      }
    }
    Logger.print(
      '[GroupRequests][handler] load=$generation '
      'processed=${missingID + missingNickname + resolved} '
      'missingHandlerID=$missingID missingNickname=$missingNickname '
      'resolved=$resolved profileLookup=$profileLookup',
      onlyConsole: true,
    );

    Logger.print(
        '[GroupRequests][profiles] elapsedMs=${watch.elapsedMilliseconds}',
        onlyConsole: true);
  }

  void getJoinedGroup() {
    if (!isSessionActive) return;
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    OpenIM.iMManager.groupManager.getJoinedGroupList().then((list) {
      if (!isSessionActive ||
          account != OpenIM.iMManager.userID ||
          token != DataSp.chatToken) {
        return;
      }
      var map = <String, GroupInfo>{};
      for (var e in list) {
        map[e.groupID] = e;
      }
      groupList.addAll(map);
    });
  }

  String getGroupName(GroupApplicationInfo info) =>
      IMUtils.emptyStrToNull(groupList[info.groupID]?.groupName?.trim()) ??
      IMUtils.emptyStrToNull(info.groupName?.trim()) ??
      '';

  String? getGroupAvatar(GroupApplicationInfo info) =>
      IMUtils.emptyStrToNull(groupList[info.groupID]?.faceURL?.trim()) ??
      IMUtils.emptyStrToNull(info.groupFaceURL?.trim());

  Future<void> openChat(GroupApplicationInfo info) => _chatOpener.open(
      sourceID: info.groupID,
      sessionType:
          groupList[info.groupID]?.sessionType ?? ConversationType.superGroup,
      isCurrent: () => isSessionActive);

  String getInviterNickname(GroupApplicationInfo info) =>
      (getMemberInfo(info.inviterUserID!)?.nickname) ??
      (getUserInfo(info.inviterUserID!)?.nickname) ??
      '-';

  String? getHandlerNickname(GroupApplicationInfo info) {
    final id = _handlerUserID(info);
    if (id == null) return null;
    return IMUtils.emptyStrToNull(getUserInfo(id)?.nickname?.trim());
  }

  String? _handlerUserID(GroupApplicationInfo info) {
    if (info.handleResult != 1 && info.handleResult != -1) return null;
    return IMUtils.emptyStrToNull(info.handleUserID?.trim());
  }

  GroupMembersInfo? getMemberInfo(String inviterUserID) =>
      memberList.firstWhereOrNull((e) => e.userID == inviterUserID);

  UserInfo? getUserInfo(String inviterUserID) =>
      userInfoList.firstWhereOrNull((e) => e.userID == inviterUserID);

  void handle(GroupApplicationInfo info) async {
    if (!isSessionActive) return;
    var result =
        await AppNavigator.startProcessGroupRequests(applicationInfo: info);
    if (isSessionActive && result is int) {
      info.handleResult = result;
      list.refresh();
      _cacheRows();
    }
  }
}
