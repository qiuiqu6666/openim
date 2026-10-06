import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../home/home_logic.dart';

class GroupRequestsLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final homeLogic = Get.find<HomeLogic>();
  final list = <GroupApplicationInfo>[].obs;
  // An empty list is conclusive only after the latest SDK read succeeds.
  final applicationsLoaded = false.obs;
  final groupList = <String, GroupInfo>{}.obs;
  final memberList = <GroupMembersInfo>[].obs;
  final userInfoList = <UserInfo>[].obs;
  final _ownerAccount = OpenIM.iMManager.userID;
  final _ownerToken = DataSp.chatToken;
  StreamSubscription<GroupApplicationInfo>? _applicationSubscription;
  int _loadGeneration = 0;

  bool get isSessionActive =>
      !isClosed &&
      _ownerAccount == OpenIM.iMManager.userID &&
      _ownerToken == DataSp.chatToken;

  @override
  void onReady() {
    getApplicationList();
    getJoinedGroup();
    super.onReady();
  }

  @override
  void onInit() {
    _applicationSubscription =
        imLogic.groupApplicationChangedSubject.listen((info) {
      getApplicationList();
    });
    super.onInit();
  }

  @override
  void onClose() {
    _loadGeneration++;
    _applicationSubscription?.cancel();
    homeLogic.getUnhandledGroupApplicationCount();
    super.onClose();
  }

  bool isInvite(GroupApplicationInfo info) {
    if (info.joinSource == 2) {
      return info.inviterUserID != null && info.inviterUserID!.isNotEmpty;
    }
    return false;
  }

  Future<void> getApplicationList() async {
    if (!isSessionActive) return;
    final generation = ++_loadGeneration;
    applicationsLoaded.value = false;
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    var profileLookup = 'not_needed';
    bool isCurrent() =>
        isSessionActive &&
        generation == _loadGeneration &&
        account == OpenIM.iMManager.userID &&
        token == DataSp.chatToken;
    final list = await LoadingView.singleton.wrap(asyncFunction: () async {
      if (!isCurrent()) return <GroupApplicationInfo>[];
      final list = await Future.wait([
        OpenIM.iMManager.groupManager.getGroupApplicationListAsRecipient(),
        OpenIM.iMManager.groupManager.getGroupApplicationListAsApplicant(),
      ]);

      final allList = <GroupApplicationInfo>[];
      allList
        ..addAll(list[0])
        ..addAll(list[1]);

      if (!isCurrent()) return allList;
      allList.sort((a, b) => (b.reqTime ?? 0).compareTo(a.reqTime ?? 0));

      var map = <String, List<String>>{};
      final profileIDs = <String>{};

      var haveReadList = DataSp.getHaveReadUnHandleGroupApplication();
      haveReadList ??= <String>[];
      for (var a in list[0]) {
        var id = IMUtils.buildGroupApplicationID(a);
        if (!haveReadList.contains(id)) {
          haveReadList.add(id);
        }
      }
      DataSp.putHaveReadUnHandleGroupApplication(haveReadList);

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

      if (map.isNotEmpty) {
        try {
          final members = await Future.wait(map.entries.map((e) => OpenIM
              .iMManager.groupManager
              .getGroupMembersInfo(groupID: e.key, userIDList: e.value)));
          if (isCurrent()) {
            memberList.assignAll(members.expand((group) => group));
          }
        } catch (error) {
          Logger.print(
              'Group application member lookup failed: ${error.runtimeType}');
        }
      }

      if (!isCurrent()) return allList;
      if (profileIDs.isNotEmpty) {
        try {
          final profiles = await OpenIM.iMManager.userManager
              .getUsersInfo(userIDList: profileIDs.toList());
          profileLookup = 'succeeded';
          if (isCurrent()) {
            userInfoList.assignAll(profiles.map((e) => e.simpleUserInfo));
          }
        } catch (error) {
          profileLookup = 'failed';
          // Profile availability must not hide the application's actual result.
          Logger.print(
              'Group application user lookup failed: ${error.runtimeType}');
        }
      }

      return allList;
    });

    if (isCurrent()) {
      this.list.assignAll(list);
      applicationsLoaded.value = true;
      final processed = list
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
    }
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
      info.groupName ?? groupList[info.groupID]?.groupName ?? '';

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
    }
  }
}
