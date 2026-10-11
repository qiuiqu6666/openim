import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../../core/controller/im_controller.dart';
import '../../../core/im_callback.dart';
import '../../conversation/conversation_logic.dart';
import '../../group_features/data/group_feature_runtime.dart';
import 'search/group_list_search.dart';

class GroupListLogic extends GetxController {
  GroupListLogic({
    Future<List<GroupInfo>> Function(int offset, int count)? fetchPage,
    String Function()? currentUserID,
    Future<List<GroupInfo>> Function(String)? findGroups,
  })  : _fetchPage = fetchPage ??
            ((offset, count) => OpenIM.iMManager.groupManager
                .getJoinedGroupListPage(offset: offset, count: count)),
        _currentUserID = currentUserID ?? (() => OpenIM.iMManager.userID),
        _findGroups = findGroups;

  final Future<List<GroupInfo>> Function(int, int) _fetchPage;
  final String Function() _currentUserID;
  final Future<List<GroupInfo>> Function(String)? _findGroups;
  GroupListSearch? _search;
  GroupListSearch get search => _search ??= GroupListSearch(
      findGroups: _findGroups,
      currentUserID: _currentUserID,
      onResults: _seedGroups);
  final iCreateRefreshController = RefreshController();
  final iJoinRefreshController = RefreshController();
  final iCreateGlobalKey = GlobalKey();
  final iJoinGlobalKey = GlobalKey();
  ConversationLogic get conversationLogic => Get.find<ConversationLogic>();
  GroupFeatureStore? get groupFeatures => Get.isRegistered<IMController>()
      ? GroupFeatureRuntime.forAccount(Get.find<IMController>())
      : null;
  final index = 0.obs;
  final iCreatedList = <GroupInfo>[].obs;
  final iJoinedList = <GroupInfo>[].obs;
  final loading = <bool, bool>{true: true, false: true}.obs;
  final loadFailed = <bool, bool>{true: false, false: false}.obs;
  int iCreatedOffset = 0;
  int iJoinedOffset = 0;
  int count = 100;
  final _versions = <bool, int>{true: 0, false: 0};
  final _loading = <bool, bool>{true: false, false: false};
  final _hasMore = <bool, bool>{true: true, false: true};
  StreamSubscription? _syncSubscription;
  bool _disposed = false;

  @override
  void onInit() {
    super.onInit();
    _syncSubscription =
        (Get.isRegistered<IMController>() ? Get.find<IMController>() : null)
            ?.imSdkStatusPublishSubject
            .listen((event) {
      if (event.status == IMSdkStatus.syncEnded) {
        iCreatedInitial();
        iJoinedInitial();
        _search?.run();
      }
    });
    iCreatedInitial();
    iJoinedInitial();
  }

  void switchTab(int i) => index.value = i;

  bool canLoadMore(bool iCreate) => _hasMore[iCreate]!;

  bool isComplete(bool iCreate) =>
      !loading[iCreate]! && !loadFailed[iCreate]! && !_hasMore[iCreate]!;

  Future<void> iCreatedInitial() => _load(iCreate: true, refresh: true);
  Future<void> iJoinedInitial() => _load(iCreate: false, refresh: true);
  Future<void> iCreatedLoadMore() => _load(iCreate: true, refresh: false);
  Future<void> iJoinedLoadMore() => _load(iCreate: false, refresh: false);

  void _seedGroups(List<GroupInfo> groups) {
    final features = groupFeatures;
    if (features != null) {
      for (final group in groups) {
        features.seed(group);
      }
    }
  }

  Future<void> _load({required bool iCreate, required bool refresh}) async {
    if (_disposed ||
        (!refresh && (_loading[iCreate]! || !_hasMore[iCreate]!))) {
      return;
    }
    // A refresh supersedes any older refresh or pagination request.
    final version = _versions[iCreate]! + 1;
    _versions[iCreate] = version;
    _loading[iCreate] = true;
    loading[iCreate] = true;
    loadFailed[iCreate] = false;
    final controller =
        iCreate ? iCreateRefreshController : iJoinRefreshController;
    final target = iCreate ? iCreatedList : iJoinedList;
    var offset = refresh ? 0 : (iCreate ? iCreatedOffset : iJoinedOffset);
    final userID = _currentUserID();
    final token = DataSp.chatToken;
    try {
      final groups = <String, GroupInfo>{
        if (!refresh)
          for (final group in target) group.groupID: group,
      };
      final previousLength = groups.length;
      final received = <GroupInfo>[];
      var hasMore = true;
      // Preserve SDK order and load only until this tab gains rows. A page
      // containing only the other ownership category is not an empty directory.
      while (true) {
        final page = await _fetchPage(offset, count);
        if (_disposed ||
            _versions[iCreate] != version ||
            _currentUserID() != userID ||
            DataSp.chatToken != token) {
          return;
        }
        for (final group in page) {
          if (group.groupID.isNotEmpty &&
              (group.ownerUserID == userID) == iCreate) {
            groups[group.groupID] = group;
            received.add(group);
          }
        }
        // SDK offsets refer to the unfiltered page, not either ownership tab.
        offset += page.length;
        hasMore = page.length >= count;
        if (!hasMore || groups.length > previousLength) break;
      }
      _seedGroups(received);
      target.assignAll(groups.values);
      if (iCreate) {
        iCreatedOffset = offset;
      } else {
        iJoinedOffset = offset;
      }
      _hasMore[iCreate] = hasMore;
      if (refresh) controller.refreshCompleted(resetFooterState: true);
      if (_hasMore[iCreate]!) {
        controller.loadComplete();
      } else {
        controller.loadNoData();
      }
    } catch (_) {
      if (_disposed || _versions[iCreate] != version) return;
      loadFailed[iCreate] = true;
      if (refresh) {
        controller.refreshFailed();
      } else {
        controller.loadFailed();
      }
    } finally {
      if (!_disposed && _versions[iCreate] == version) {
        _loading[iCreate] = false;
        loading[iCreate] = false;
      }
    }
  }

  @override
  void onClose() {
    _disposed = true;
    _syncSubscription?.cancel();
    _search?.dispose();
    iCreateRefreshController.dispose();
    iJoinRefreshController.dispose();
    super.onClose();
  }

  void toGroupChat(GroupInfo info) {
    conversationLogic.toChat(
      offUntilHome: false,
      groupID: info.groupID,
      nickname: info.groupName,
      faceURL: info.faceURL,
      sessionType: info.sessionType,
    );
  }
}
