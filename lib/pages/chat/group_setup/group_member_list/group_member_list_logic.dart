import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';

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
import '../../group/identity/group_member_identity.dart';
import 'group_member_identity_state.dart';

enum GroupMemberOpType {
  view,
  transferRight,
  call,
  at,
  del,
}

class GroupMemberListLogic extends GetxController with WidgetsBindingObserver {
  GroupMemberListLogic({GroupMemberIdentityState? identity})
      : identity = identity ?? GroupMemberIdentityState();

  final GroupMemberIdentityState identity;
  String displayedAccount(GroupMembersInfo member) => identity.isCurrentSession
      ? GroupMemberIdentityState.accountOf(member)
      : '';
  IMController get imLogic => Get.find<IMController>();
  GroupSetupLogic get groupSetupLogic => Get.find<GroupSetupLogic>();
  final controller = RefreshController();
  final presence = PresenceStore();
  final _visibleIDs = <String>{};
  Timer? _presenceDebounce;
  Timer? _presencePoll;
  StreamSubscription? _presenceSubscription;
  bool _refreshingPresence = false;
  bool _refreshingIdentityRules = false;
  bool _foreground = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_refreshPresence());
      unawaited(_refreshIdentityRules());
    }
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
    if (!identity.isCurrentSession || isClosed) return;
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
    if (query.isEmpty ||
        isClosed ||
        !identity.isCurrentSession ||
        (next && searching.value)) return;
    final version = ++_searchVersion;
    final identityGeneration = identity.generation;
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
      if (isClosed ||
          version != _searchVersion ||
          !identity.active(identityGeneration)) return;
      final enriched =
          await identity.searchIdentities(groupInfo.groupID, results);
      if (enriched == null ||
          isClosed ||
          version != _searchVersion ||
          !identity.active(identityGeneration)) return;
      _searchOffset += results.length;
      searchResults.addAll(enriched);
      searchMore.value = results.length == 50;
    } catch (_) {
      if (!isClosed &&
          version == _searchVersion &&
          identity.active(identityGeneration)) searchFailed.value = true;
    } finally {
      if (!isClosed &&
          version == _searchVersion &&
          identity.active(identityGeneration)) searching.value = false;
    }
  }

  final checkedList = <GroupMembersInfo>[].obs;
  final poController = CustomPopupMenuController();
  int count = 100;
  int _pageNumber = 1;
  bool _loadingMembers = false;
  final myGroupMemberLevel = 1.obs;
  int _myAppManagerLevel = 0;
  late GroupInfo groupInfo;
  int? _lastLookMemberInfo;
  late GroupMemberOpType opType;
  StreamSubscription? mISub;
  StreamSubscription? _groupInfoSubscription;
  StreamSubscription? _memberDeletedSubscription;
  StreamSubscription? _groupDeletedSubscription;
  StreamSubscription? _selfInfoSubscription;

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

  int get maxLength => isDelMember
      ? max(groupInfo.memberCount ?? 0, visibleMembers.length)
      : min(groupInfo.memberCount ?? 10, 10);

  @override
  void onClose() {
    identity.close();
    _clearIdentityState();
    WidgetsBinding.instance.removeObserver(this);
    _searchVersion++;
    _searchTimer?.cancel();
    searchController.dispose();
    mISub?.cancel();
    _groupInfoSubscription?.cancel();
    _memberDeletedSubscription?.cancel();
    _groupDeletedSubscription?.cancel();
    _selfInfoSubscription?.cancel();
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
    _lastLookMemberInfo = groupInfo.lookMemberInfo;
    opType = Get.arguments['opType'];
    mISub = imLogic.memberInfoChangedSubject.listen(onGroupMemberChanged);
    _groupInfoSubscription =
        imLogic.groupInfoUpdatedSubject.listen(onGroupIdentityRulesChanged);
    _memberDeletedSubscription =
        imLogic.memberDeletedSubject.listen(onGroupMemberDeleted);
    _groupDeletedSubscription =
        imLogic.joinedGroupDeletedSubject.listen(onJoinedGroupDeleted);
    final selfInfo = imLogic.selfInfoUpdatedSubject;
    _selfInfoSubscription = (selfInfo.hasValue ? selfInfo.skip(1) : selfInfo)
        .listen(onSelfInfoUpdated);
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

  void onGroupMemberChanged(GroupMembersInfo e) {
    if (isClosed ||
        !identity.isCurrentSession ||
        e.groupID != groupInfo.groupID) return;
    if (e.userID == OpenIM.iMManager.userID &&
        ((e.roleLevel != null && e.roleLevel != myGroupMemberLevel.value) ||
            (e.appManagerLevel != null &&
                e.appManagerLevel != _myAppManagerLevel))) {
      if (e.roleLevel != null) myGroupMemberLevel.value = e.roleLevel!;
      if (e.appManagerLevel != null) _myAppManagerLevel = e.appManagerLevel!;
      _reloadIdentity();
      return;
    }
    for (final list in [memberList, searchResults]) {
      final index = list.indexWhere((m) => m.userID == e.userID);
      if (index >= 0) {
        list[index] = GroupMemberIdentityState.mergeEvent(e, list[index]);
        list.sort(compareGroupMembers);
      }
    }
  }

  void onSelfInfoUpdated(UserInfo value) {
    if (isClosed ||
        !identity.isCurrentSession ||
        value.userID != OpenIM.iMManager.userID) {
      return;
    }
    _reloadIdentity();
    unawaited(_queryMyGroupMemberLevel(loadMembers: false));
  }

  void onGroupIdentityRulesChanged(GroupInfo value) {
    if (isClosed ||
        !identity.isCurrentSession ||
        value.groupID != groupInfo.groupID) return;
    final changed = value.lookMemberInfo !=
        (_lastLookMemberInfo ?? groupInfo.lookMemberInfo);
    _lastLookMemberInfo = value.lookMemberInfo;
    groupInfo = value;
    if (changed) _reloadIdentity();
  }

  void onGroupMemberDeleted(GroupMembersInfo value) {
    if (isClosed ||
        !identity.isCurrentSession ||
        value.groupID != groupInfo.groupID) return;
    final userID = value.userID;
    if (userID == OpenIM.iMManager.userID) {
      onJoinedGroupDeleted(groupInfo);
      return;
    }
    if (userID == null || userID.isEmpty) return;
    for (final list in [memberList, searchResults, checkedList]) {
      for (final member in list.where((member) => member.userID == userID)) {
        if (member is GroupMemberIdentityInfo) member.account = null;
      }
      list.removeWhere((member) => member.userID == userID);
    }
    _visibleIDs.remove(userID);
    presence.stopWatching(userID);
  }

  void onJoinedGroupDeleted(GroupInfo value) {
    if (isClosed || value.groupID != groupInfo.groupID) return;
    identity.close();
    _clearIdentityState();
  }

  Future<void> _refreshIdentityRules() async {
    if (isClosed || !identity.isCurrentSession || _refreshingIdentityRules)
      return;
    _refreshingIdentityRules = true;
    identity.invalidate();
    _clearIdentityState();
    final request = identity.generation;
    try {
      final rules = await identity.rules(groupInfo.groupID);
      if (rules == null || isClosed || !identity.active(request)) return;
      final latest = rules.group;
      final me = rules.self;
      if (latest != null) {
        groupInfo = latest;
        _lastLookMemberInfo = latest.lookMemberInfo;
      }
      if (me != null) {
        myGroupMemberLevel.value = me.roleLevel ?? GroupRoleLevel.member;
        _myAppManagerLevel = me.appManagerLevel ?? 0;
      }
    } catch (_) {
      // Account visibility is still revalidated by the authoritative list below.
    } finally {
      if (!isClosed && identity.active(request)) await onLoad();
      _refreshingIdentityRules = false;
    }
  }

  void _clearIdentityState() {
    _searchVersion++;
    _searchTimer?.cancel();
    for (final list in [memberList, searchResults, checkedList]) {
      for (final member in list) {
        if (member is GroupMemberIdentityInfo) member.account = null;
      }
      list.clear();
    }
    searchController.clear();
    query.value = '';
    _searchOffset = 0;
    searching.value = false;
    searchFailed.value = false;
    searchMore.value = false;
    _pageNumber = 1;
    _loadingMembers = false;
    for (final id in _visibleIDs) {
      presence.stopWatching(id);
    }
    _visibleIDs.clear();
    controller.resetNoData();
  }

  void _reloadIdentity() {
    identity.invalidate();
    _clearIdentityState();
    unawaited(onLoad());
  }

  Future<void> _queryMyGroupMemberLevel({bool loadMembers = true}) async {
    final request = identity.generation;
    try {
      final list = await identity.source.members(
        groupID: groupInfo.groupID,
        userIDList: [OpenIM.iMManager.userID],
      );
      if (isClosed || !identity.active(request)) return;
      final myInfo = list.firstWhereOrNull(
          (member) => member.userID == OpenIM.iMManager.userID);
      if (null != myInfo) {
        myGroupMemberLevel.value = myInfo.roleLevel ?? GroupRoleLevel.member;
        _myAppManagerLevel = myInfo.appManagerLevel ?? 0;
      }
      if (loadMembers) await onLoad();
    } catch (_) {
      if (loadMembers && !isClosed && identity.active(request)) {
        controller.loadFailed();
      }
    }
  }

  Future<void> onLoad() async {
    if (_loadingMembers || isClosed || !identity.isCurrentSession) return;
    final request = identity.generation;
    _loadingMembers = true;
    try {
      final list = await identity.list(
          groupID: groupInfo.groupID,
          pageNumber: _pageNumber,
          showNumber: count);
      if (list == null || isClosed || !identity.active(request)) return;
      final known = memberList.map((member) => member.userID).toSet();
      memberList.addAll(list.where((member) => known.add(member.userID)));
      ++_pageNumber;
      if (list.length < count) {
        controller.loadNoData();
      } else {
        controller.loadComplete();
      }
    } catch (_) {
      if (!isClosed && identity.active(request)) controller.loadFailed();
    } finally {
      if (identity.active(request)) _loadingMembers = false;
    }
  }

  bool isChecked(GroupMembersInfo membersInfo) =>
      checkedList.any((member) => member.userID == membersInfo.userID);

  bool get isAllVisibleSelected =>
      visibleMembers.isNotEmpty && visibleMembers.every(isChecked);

  void toggleSelectAllVisible() {
    if (!isDelMember || isClosed || searching.value) return;
    final members = visibleMembers;
    if (members.isEmpty) return;
    if (isAllVisibleSelected) {
      final ids = members.map((member) => member.userID).toSet();
      checkedList.removeWhere((member) => ids.contains(member.userID));
    } else {
      for (final member in members) {
        if (checkedList.length >= maxLength) break;
        if (!isChecked(member)) checkedList.add(member);
      }
    }
  }

  clickMember(GroupMembersInfo membersInfo) async {
    if (isClosed || !identity.isCurrentSession) return;
    if (opType == GroupMemberOpType.transferRight) {
      _transferGroupRight(membersInfo);
      return;
    }
    if (isMultiSelMode) {
      if (isChecked(membersInfo)) {
        checkedList
            .removeWhere((member) => member.userID == membersInfo.userID);
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
    checkedList.removeWhere((member) => member.userID == membersInfo.userID);
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
    if (!isClosed && identity.isCurrentSession) _reloadIdentity();
  }

  void delMember() async {
    poController.hideMenu();
    await groupSetupLogic.removeMember();
    refreshData();
  }

  void search() async {
    final request = identity.generation;
    final memberInfo = await AppNavigator.startSearchGroupMember(
      groupInfo: groupInfo,
      opType: opType,
    );
    if (memberInfo is! GroupMembersInfo ||
        isClosed ||
        !identity.active(request)) return;
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
