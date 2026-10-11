import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../home/home_logic.dart';
import '../request_history/data/request_history_store.dart';

class FriendRequestsLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final homeLogic = Get.find<HomeLogic>();
  final applicationList = <FriendApplicationInfo>[].obs;
  final loading = true.obs;
  final loadFailed = false.obs;
  final cleaning = false.obs;
  final _ownerAccount = OpenIM.iMManager.userID;
  final _ownerToken = DataSp.chatToken;
  late final _history =
      RequestHistoryStore(_ownerAccount, RequestHistoryKind.friend);
  int _loadVersion = 0;
  late StreamSubscription faSub;

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

  Future<void> _clean(Future<void> Function() save) async {
    if (!isSessionActive || cleaning.value) return;
    cleaning.value = true;
    try {
      await save();
      if (!isSessionActive) return;
      applicationList.removeWhere((item) => !_visible(item));
      homeLogic.getUnhandledFriendApplicationCount();
    } catch (_) {
      if (isSessionActive) IMViews.showToast('requestHistoryCleanupFailed'.tr);
    } finally {
      if (!isClosed) cleaning.value = false;
    }
  }

  @override
  void onInit() {
    faSub = imLogic.friendApplicationChangedSubject.listen((value) {
      loadRequests();
    });
    super.onInit();
  }

  @override
  void onReady() {
    loadRequests();
    super.onReady();
  }

  @override
  void onClose() {
    _loadVersion++;
    faSub.cancel();
    homeLogic.getUnhandledFriendApplicationCount();
    super.onClose();
  }

  Future<void> loadRequests() async {
    if (!isSessionActive) return;
    final version = ++_loadVersion;
    loading.value = true;
    loadFailed.value = false;
    try {
      final list = await Future.wait([
        OpenIM.iMManager.friendshipManager
            .getFriendApplicationListAsRecipient(),
        OpenIM.iMManager.friendshipManager
            .getFriendApplicationListAsApplicant(),
      ]);
      if (!isSessionActive || version != _loadVersion) return;

      final allList = <FriendApplicationInfo>[];
      allList
        ..addAll(list[0])
        ..addAll(list[1]);

      allList.sort((a, b) => (b.createTime ?? 0).compareTo(a.createTime ?? 0));

      var haveReadList = DataSp.getHaveReadUnHandleFriendApplication();
      haveReadList ??= <String>[];
      for (var e in list[0]) {
        var id = IMUtils.buildFriendApplicationID(e);
        if (!haveReadList.contains(id)) {
          haveReadList.add(id);
        }
      }
      DataSp.putHaveReadUnHandleFriendApplication(haveReadList);
      final seen = <String>{};
      applicationList.assignAll(allList.where((item) =>
          _visible(item) && seen.add(RequestHistoryEntry.friend(item).id)));
    } catch (_) {
      if (isSessionActive && version == _loadVersion) loadFailed.value = true;
    } finally {
      if (isSessionActive && version == _loadVersion) loading.value = false;
    }
  }

  bool isISendRequest(FriendApplicationInfo info) =>
      info.fromUserID == OpenIM.iMManager.userID;

  void acceptFriendApplication(FriendApplicationInfo info) =>
      AppNavigator.startProcessFriendRequests(
        applicationInfo: info,
      );

  void refuseFriendApplication(FriendApplicationInfo info) async {}
}
