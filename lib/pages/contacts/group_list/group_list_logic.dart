import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../../core/controller/im_controller.dart';
import '../../../core/im_callback.dart';
import '../../conversation/conversation_logic.dart';
import '../../group_features/data/group_feature_runtime.dart';

class GroupListLogic extends GetxController {
  GroupListLogic({
    Future<List<GroupInfo>> Function(int offset, int count)? fetchPage,
    String Function()? currentUserID,
  })  : _fetchPage = fetchPage ??
            ((offset, count) => OpenIM.iMManager.groupManager
                .getJoinedGroupListPage(offset: offset, count: count)),
        _currentUserID = currentUserID ?? (() => OpenIM.iMManager.userID);

  final Future<List<GroupInfo>> Function(int, int) _fetchPage;
  final String Function() _currentUserID;
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
  int count = 1000;
  final _versions = <bool, int>{true: 0, false: 0};
  final _loading = <bool, bool>{true: false, false: false};
  final _hasMore = <bool, bool>{true: true, false: true};
  StreamSubscription? _syncSubscription;
  bool _disposed = false;

  @override
  void onInit() {
    super.onInit();
    _syncSubscription =
        Get.find<IMController>().imSdkStatusPublishSubject.listen((event) {
      if (event.status == IMSdkStatus.syncEnded) {
        iCreatedInitial();
        iJoinedInitial();
      }
    });
    iCreatedInitial();
    iJoinedInitial();
  }

  void switchTab(int i) => index.value = i;

  bool canLoadMore(bool iCreate) =>
      !loading[iCreate]! && !loadFailed[iCreate]! && _hasMore[iCreate]!;

  Future<void> iCreatedInitial() => _load(iCreate: true, refresh: true);
  Future<void> iJoinedInitial() => _load(iCreate: false, refresh: true);
  Future<void> iCreatedLoadMore() => _load(iCreate: true, refresh: false);
  Future<void> iJoinedLoadMore() => _load(iCreate: false, refresh: false);

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
    final offset = refresh ? 0 : (iCreate ? iCreatedOffset : iJoinedOffset);
    try {
      final page = await _fetchPage(offset, count);
      if (_disposed || _versions[iCreate] != version) return;
      final features = groupFeatures;
      if (features != null) {
        for (final group in page) {
          features.seed(group);
        }
      }
      final groups = <String?, GroupInfo>{
        if (!refresh)
          for (final group in target) group.groupID: group,
        for (final group in page)
          if ((group.ownerUserID == _currentUserID()) == iCreate)
            group.groupID: group,
      };
      target.assignAll(groups.values);
      // SDK offsets refer to the unfiltered page, not either ownership tab.
      if (iCreate) {
        iCreatedOffset = offset + page.length;
      } else {
        iJoinedOffset = offset + page.length;
      }
      _hasMore[iCreate] = page.length >= count;
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
