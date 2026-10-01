import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:sprintf/sprintf.dart';

import '../../../../core/controller/im_controller.dart';
import '../group_setup_logic.dart';
import '../group_member_order.dart';
import '../../../contacts/presence_store.dart';

enum GroupMemberOpType {
  view,
  transferRight,
  call,
  at,
  del,
}

class GroupMemberListLogic extends GetxController with WidgetsBindingObserver {
  final imLogic = Get.find<IMController>();
  GroupSetupLogic get groupSetupLogic => Get.find<GroupSetupLogic>();
  final controller = RefreshController();
  final presence = PresenceStore();
  final _visibleIDs = <String>{};
  Timer? _presenceDebounce;
  Timer? _presencePoll;
  StreamSubscription? _presenceSubscription;
  bool _refreshingPresence = false;
  bool _foreground = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refreshPresence());
  }

  void setPresenceVisible(String id, bool visible) {
    if (isClosed) return;
    if (visible) {
      _visibleIDs.add(id);
    } else {
      _visibleIDs.remove(id);
      presence.stopWatching(id);
    }
    _presenceDebounce?.cancel();
    _presenceDebounce =
        Timer(const Duration(milliseconds: 250), _refreshPresence);
  }

  Future<void> _refreshPresence() async {
    if (isClosed || !_foreground || _refreshingPresence || _visibleIDs.isEmpty)
      return;
    _refreshingPresence = true;
    try {
      await presence.refresh(_visibleIDs.toList());
    } finally {
      _refreshingPresence = false;
    }
  }

  final memberList = <GroupMembersInfo>[].obs;
  final searchController = TextEditingController();
  final searchResults = <GroupMembersInfo>[].obs;
  final query = ''.obs;
  final searching = false.obs;
  final searchFailed = false.obs;
  final searchMore = false.obs;
  Timer? _searchTimer;
  int _searchVersion = 0, _searchOffset = 0;
  List<GroupMembersInfo> get visibleMembers =>
      (query.isEmpty ? memberList : searchResults)
          .where((m) =>
              !hiddenMember(m) &&
              (!isDelMember ||
                  (m.userID != OpenIM.iMManager.userID &&
                      (isOwner
                          ? m.roleLevel != GroupRoleLevel.owner
                          : isAdmin && m.roleLevel == GroupRoleLevel.member))))
          .toList()
        ..sort(compareGroupMembers);

  void searchChanged(String value) {
    _searchTimer?.cancel();
    _searchVersion++;
    query.value = value.trim();
    searchResults.clear();
    _searchOffset = 0;
    searchFailed.value = false;
    searchMore.value = false;
    searching.value = query.isNotEmpty;
    if (query.isNotEmpty)
      _searchTimer =
          Timer(const Duration(milliseconds: 300), () => searchMembers());
  }

  Future<void> searchMembers({bool next = false}) async {
    _searchTimer?.cancel();
    if (query.isEmpty || isClosed || (next && searching.value)) return;
    final version = ++_searchVersion;
    if (!next) {
      _searchOffset = 0;
      searchResults.clear();
    }
    searching.value = true;
    searchFailed.value = false;
    try {
      final results = await OpenIM.iMManager.groupManager.searchGroupMembers(
          groupID: groupInfo.groupID,
          keywordList: [query.value],
          isSearchUserID: true,
          isSearchMemberNickname: true,
          offset: _searchOffset,
          count: 50);
      if (isClosed || version != _searchVersion) return;
      _searchOffset += results.length;
      searchResults.addAll(results);
      searchMore.value = results.length == 50;
    } catch (_) {
      if (!isClosed && version == _searchVersion) searchFailed.value = true;
    } finally {
      if (!isClosed && version == _searchVersion) searching.value = false;
    }
  }

  final checkedList = <GroupMembersInfo>[].obs;
  final poController = CustomPopupMenuController();
  int count = 500;
  final myGroupMemberLevel = 1.obs;
  late GroupInfo groupInfo;
  late GroupMemberOpType opType;
  late StreamSubscription mISub;

  bool get isMultiSelMode =>
      opType == GroupMemberOpType.call ||
      opType == GroupMemberOpType.at ||
      opType == GroupMemberOpType.del;

  bool get excludeSelfFromList =>
      opType == GroupMemberOpType.call ||
      opType == GroupMemberOpType.at ||
      opType == GroupMemberOpType.transferRight;

  bool get isDelMember => opType == GroupMemberOpType.del;

  bool get isAdmin => myGroupMemberLevel.value == GroupRoleLevel.admin;

  bool get isOwner => myGroupMemberLevel.value == GroupRoleLevel.owner;

  bool get isOwnerOrAdmin => isAdmin || isOwner;

  int get maxLength => min(groupInfo.memberCount!, 10);

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchVersion++;
    _searchTimer?.cancel();
    searchController.dispose();
    mISub.cancel();
    _presenceSubscription?.cancel();
    _presenceDebounce?.cancel();
    _presencePoll?.cancel();
    presence.dispose();
    controller.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    groupInfo = Get.arguments['groupInfo'];
    opType = Get.arguments['opType'];
    mISub = imLogic.memberInfoChangedSubject.listen(_updateMemberLevel);
    _presenceSubscription = imLogic.userStatusChangedSubject.listen((event) {
      if (_visibleIDs.contains(event.userID)) {
        unawaited(_refreshPresence());
      }
    });
    _presencePoll =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshPresence());
    super.onInit();
  }

  @override
  void onReady() {
    _queryMyGroupMemberLevel();
    super.onReady();
  }

  void _updateMemberLevel(GroupMembersInfo e) {
    if (e.groupID == groupInfo.groupID) {
      equal(GroupMembersInfo el) => el.userID == e.userID;
      final member = memberList.firstWhereOrNull(equal);
      if (null != member && e.roleLevel != member.roleLevel) {
        member.roleLevel = e.roleLevel;
      }
      for (final list in [memberList, searchResults]) {
        final index = list.indexWhere((m) => m.userID == e.userID);
        if (index >= 0) list[index] = e;
        list.sort(compareGroupMembers);
      }
    }
  }

  void _queryMyGroupMemberLevel() async {
    LoadingView.singleton.wrap(asyncFunction: () async {
      final list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupID: groupInfo.groupID,
        userIDList: [OpenIM.iMManager.userID],
      );
      final myInfo = list.firstOrNull;
      if (null != myInfo) {
        myGroupMemberLevel.value = myInfo.roleLevel ?? 1;
      }
      await onLoad();
    });
  }

  Future<List<GroupMembersInfo>> _getGroupMembers() {
    final result = OpenIM.iMManager.groupManager.getGroupMemberList(
      groupID: groupInfo.groupID,
      count: count,
      offset: memberList.length,
      filter: isDelMember ? (isOwner ? 4 : (isAdmin ? 3 : 0)) : 0,
    );

    count = 100;

    return result;
  }

  onLoad() async {
    final list = await _getGroupMembers();
    memberList.addAll(list);

    if (list.length < count) {
      controller.loadNoData();
    } else {
      controller.loadComplete();
    }
  }

  bool isChecked(GroupMembersInfo membersInfo) =>
      checkedList.contains(membersInfo);

  clickMember(GroupMembersInfo membersInfo) async {
    if (opType == GroupMemberOpType.transferRight) {
      _transferGroupRight(membersInfo);
      return;
    }
    if (isMultiSelMode) {
      if (isChecked(membersInfo)) {
        checkedList.remove(membersInfo);
      } else if (checkedList.length < maxLength) {
        checkedList.add(membersInfo);
      }
    } else {
      viewMemberInfo(membersInfo);
    }
  }

  static _transferGroupRight(GroupMembersInfo membersInfo) async {
    var confirm = await Get.dialog(CustomDialog(
      title: sprintf(StrRes.confirmTransferGroupToUser, [membersInfo.nickname]),
    ));
    if (confirm == true) {
      Get.back(result: membersInfo);
    }
  }

  void removeSelectedMember(GroupMembersInfo membersInfo) {
    checkedList.remove(membersInfo);
  }

  viewMemberInfo(GroupMembersInfo membersInfo) =>
      AppNavigator.startUserProfilePane(
        userID: membersInfo.userID!,
        groupID: membersInfo.groupID,
        nickname: membersInfo.nickname,
        faceURL: membersInfo.faceURL,
      );

  void addMember() async {
    poController.hideMenu();
    await groupSetupLogic.addMember();
    refreshData();
  }

  void refreshData() {
    LoadingView.singleton.wrap(asyncFunction: () async {
      memberList.clear();
      await onLoad();
    });
  }

  void delMember() async {
    poController.hideMenu();
    await groupSetupLogic.removeMember();
    refreshData();
  }

  void search() async {
    final memberInfo = await AppNavigator.startSearchGroupMember(
      groupInfo: groupInfo,
      opType: opType,
    );
    if (memberInfo is! GroupMembersInfo || isClosed) return;
    if (opType == GroupMemberOpType.transferRight) {
      Get.back(result: memberInfo);
    } else if (isMultiSelMode) {
      clickMember(memberInfo);
    }
  }

  static _buildEveryoneMemberInfo() => GroupMembersInfo(
        userID: OpenIM.iMManager.conversationManager.atAllTag,
        nickname: StrRes.everyone,
      );

  void selectEveryone() {
    Get.back(result: <GroupMembersInfo>[_buildEveryoneMemberInfo()]);
  }

  void confirmSelectedMember() {
    Get.back(result: checkedList.toList());
  }

  bool hiddenMember(GroupMembersInfo membersInfo) =>
      excludeSelfFromList && membersInfo.userID == OpenIM.iMManager.userID;
}
