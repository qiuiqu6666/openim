import 'dart:async';
import 'package:dio/dio.dart';

import 'package:collection/collection.dart';
import 'package:common_utils/common_utils.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';
import 'package:openim_live/openim_live.dart';

import '../../../core/controller/app_controller.dart';
import '../../../core/controller/im_controller.dart';
import '../../conversation/conversation_logic.dart';
import '../contacts_logic.dart';
import '../../../services/common_group_count_service.dart';
import '../common_groups/common_groups_page.dart';
import '../../mine/settings/pages/chat_background_page.dart';
import '../../chat/chat_logic.dart';

class UserProfilePanelLogic extends GetxController {
  Future<void> setChatBackground() async {
    final user = userInfo.value;
    final targetID = user.userID;
    if (targetID == null || targetID.isEmpty) return;
    await Get.to(() => ChatBackgroundPage(
          conversationId: targetID,
          conversationName: user.remark?.trim().isNotEmpty == true
              ? user.remark!
              : user.nickname ?? '',
        ));
    if (Get.isRegistered<ChatLogic>(tag: GetTags.chat)) {
      final chat = Get.find<ChatLogic>(tag: GetTags.chat);
      if (!chat.isClosed && chat.otherId == targetID) {
        await chat.reloadChatBackground();
      }
    }
  }

  final appLogic = Get.find<AppController>();
  final imLogic = Get.find<IMController>();
  final conversationLogic = Get.find<ConversationLogic>();
  late Rx<UserFullInfo> userInfo;
  GroupMembersInfo? groupMembersInfo;
  GroupInfo? groupInfo;
  String? groupID;
  FriendAddSource addSource = FriendAddSource.chat;
  Map<String, String> friendAddFields = const {};
  bool? offAllWhenDelFriend = false;
  bool? forceCanAdd = false;
  final iHasMutePermissions = false.obs;
  final iAmOwner = false.obs;
  final mutedTime = "".obs;
  final onlineStatus = false.obs;
  final onlineStatusDesc = ''.obs;
  final groupUserNickname = "".obs;
  final joinGroupTime = 0.obs;
  final joinGroupMethod = ''.obs;
  final inviterID = ''.obs;
  final inviterName = ''.obs;
  final hasAdminPermission = false.obs;
  final notAllowLookGroupMemberProfiles = true.obs;
  final notAllowAddGroupMemberFriend = false.obs;
  final iHaveAdminOrOwnerPermission = false.obs;
  int _profileRequest = 0;
  final commonGroupCount = RxnInt();
  final loadingCommonGroups = true.obs;
  final commonGroupsFailed = false.obs;
  final _commonGroupService = CommonGroupCountService();
  final _commonGroupSubscriptions = <StreamSubscription>[];
  Timer? _commonGroupRefreshTimer;
  int _commonGroupRequest = 0;
  CancelToken? _commonGroupCancel;
  late StreamSubscription _friendAddedSub;
  late StreamSubscription _friendDeletedSub;
  late StreamSubscription _friendInfoChangedSub;
  late StreamSubscription _memberInfoChangedSub;

  @override
  void onClose() {
    _commonGroupRequest++;
    _commonGroupCancel?.cancel();
    _commonGroupRefreshTimer?.cancel();
    for (final subscription in _commonGroupSubscriptions) {
      subscription.cancel();
    }
    if (Get.isRegistered<ContactsLogic>()) {
      Get.find<ContactsLogic>().setProfilePresence(this, null);
    }
    _friendAddedSub.cancel();
    _friendInfoChangedSub.cancel();
    _memberInfoChangedSub.cancel();
    _friendDeletedSub.cancel();
    super.onClose();
  }

  @override
  void onInit() {
    userInfo = (UserFullInfo()
          ..userID = Get.arguments['userID']
          ..nickname = Get.arguments['nickname']
          ..faceURL = Get.arguments['faceURL'])
        .obs;
    groupID = Get.arguments['groupID'];
    friendAddFields =
        Map<String, String>.from(Get.arguments['friendAddFields'] ?? {});
    addSource =
        resolveFriendAddSource(Get.arguments['addSource'], groupID: groupID);
    offAllWhenDelFriend = Get.arguments['offAllWhenDelFriend'];
    forceCanAdd = Get.arguments['forceCanAdd'];

    _friendAddedSub = imLogic.friendAddSubject.listen((user) {
      if (user.userID == userInfo.value.userID) {
        userInfo.update((val) {
          val?.isFriendship = true;
        });
        _loadProfileGender(user.userID!);
      }
    });

    _friendDeletedSub = imLogic.friendDelSubject.listen((user) {
      if (user.userID == userInfo.value.userID) {
        _profileRequest++;
        userInfo.update((value) {
          value?.account = null;
          value?.isFriendship = false;
        });
        UserCacheManager().removeUserInfo(user.userID!);
        _getUsersInfo();
      }
    });

    _friendInfoChangedSub = imLogic.friendInfoChangedSubject.listen((user) {
      if (user.userID == userInfo.value.userID) {
        userInfo.update((val) {
          val?.nickname = user.nickname;
          val?.remark = user.remark;
        });

        UserCacheManager().addOrUpdateUserInfo(user.userID!, userInfo.value);
      }
    });

    _memberInfoChangedSub = imLogic.memberInfoChangedSubject.listen((value) {
      if (!isGroupMemberPage || value.groupID != groupID) return;
      if (value.userID == OpenIM.iMManager.userID) {
        iHaveAdminOrOwnerPermission.value =
            value.roleLevel == GroupRoleLevel.owner ||
                value.roleLevel == GroupRoleLevel.admin;
        iAmOwner.value = value.roleLevel == GroupRoleLevel.owner;
        _syncGroupPrivacy();
      }
      if (value.userID == userInfo.value.userID) {
        if (null != value.muteEndTime) {
          _calMuteTime(value.muteEndTime!);
        }
        groupUserNickname.value = value.nickname ?? '';
      }
    });
    super.onInit();
  }

  @override
  void onReady() {
    if (Get.isRegistered<ContactsLogic>()) {
      Get.find<ContactsLogic>()
          .setProfilePresence(this, userInfo.value.userID!);
    }
    _getUsersInfo();
    _queryGroupInfo();
    _queryGroupMemberInfo();
    if (!isMyself) {
      loadCommonGroupCount();
      _commonGroupSubscriptions.addAll([
        imLogic.joinedGroupAddedSubject.listen((_) => _refreshCommonGroups()),
        imLogic.joinedGroupDeletedSubject.listen((_) => _refreshCommonGroups()),
        imLogic.memberAddedSubject.listen(_onCommonGroupMemberChanged),
        imLogic.memberDeletedSubject.listen(_onCommonGroupMemberChanged),
      ]);
    }

    super.onReady();
  }

  bool get isMyself => userInfo.value.userID == OpenIM.iMManager.userID;

  void _onCommonGroupMemberChanged(GroupMembersInfo member) {
    if (member.userID == userInfo.value.userID ||
        member.userID == OpenIM.iMManager.userID) {
      _refreshCommonGroups();
    }
  }

  void _refreshCommonGroups() {
    _commonGroupRefreshTimer?.cancel();
    _commonGroupRefreshTimer =
        Timer(const Duration(milliseconds: 300), loadCommonGroupCount);
  }

  Future<void> loadCommonGroupCount() async {
    if (isClosed || isMyself) return;
    final request = ++_commonGroupRequest;
    final owner = DataSp.userID;
    _commonGroupCancel?.cancel();
    final cancel = _commonGroupCancel = CancelToken();
    loadingCommonGroups.value = true;
    commonGroupsFailed.value = false;
    try {
      final count = await _commonGroupService.count(userInfo.value.userID!, cancelToken: cancel);
      if (isClosed || request != _commonGroupRequest || DataSp.userID != owner) return;
      commonGroupCount.value = count;
    } catch (_) {
      if (isClosed || request != _commonGroupRequest || DataSp.userID != owner) return;
      commonGroupsFailed.value = true;
    } finally {
      if (!isClosed && request == _commonGroupRequest && DataSp.userID == owner) {
        loadingCommonGroups.value = false;
      }
    }
  }

  Future<void> openCommonGroups() async {
    await Get.to(() => CommonGroupsPage(peerUserID: userInfo.value.userID!));
    if (!isClosed) await loadCommonGroupCount();
  }

  bool get isGroupMemberPage => null != groupID && groupID!.isNotEmpty;

  bool get isFriendship => userInfo.value.isFriendship == true;

  bool get isAllowAddFriend => userInfo.value.allowAddFriend == 1;

  bool get allowSendMsgNotFriend {
    final r = null == appLogic.clientConfigMap['allowSendMsgNotFriend'] ||
        appLogic.clientConfigMap['allowSendMsgNotFriend'] == '1';
    return r;
  }

  void _getUsersInfo() async {
    final userID = userInfo.value.userID!;
    final existUser = UserCacheManager().getUserInfo(userID);
    if (existUser != null) {
      userInfo.update((val) {
        val?.nickname = existUser.nickname;
        val?.faceURL = existUser.faceURL;
        val?.status = existUser.status;
        val?.level = existUser.level;
        val?.phoneNumber = existUser.phoneNumber;
        val?.areaCode = existUser.areaCode;
        val?.birth = existUser.birth;
        val?.email = existUser.email;
        val?.gender = existUser.gender;
        val?.mobile = existUser.mobile;
        val?.ex = existUser.ex;
      });
    }

    if (userID == OpenIM.iMManager.userID) {
      final user = await OpenIM.iMManager.userManager.getSelfUserInfo();
      if (isClosed) return;

      userInfo.update((val) {
        val?.nickname = user.nickname;
        val?.faceURL = user.faceURL;
        val?.ex = user.ex;
      });

      UserCacheManager().addOrUpdateUserInfo(userID, userInfo.value);
      await _loadProfileGender(userID);
      return;
    }

    final friendInfo = (await OpenIM.iMManager.friendshipManager.getFriendsInfo(
      userIDList: [userID],
    ))
        .firstOrNull;

    final blackList = await OpenIM.iMManager.friendshipManager.getBlacklist();
    if (isClosed) return;

    final isFriendship = friendInfo != null;
    final isBlack =
        blackList.firstWhereOrNull((e) => e.userID == userID) != null;
    userInfo.update((value) {
      value?.isFriendship = isFriendship;
      value?.isBlacklist = isBlack;
    });

    if (friendInfo == null) {
      final user = (await OpenIM.iMManager.userManager.getUsersInfoWithCache(
        [userID],
      ))
          .firstOrNull;
      if (user != null) {
        if (isClosed) return;
        userInfo.update((val) {
          val?.nickname = user.nickname;
          val?.faceURL = user.faceURL;
          val?.ex = user.ex;
          val?.remark = friendInfo?.remark;
          val?.isBlacklist = isBlack;
          val?.isFriendship = isFriendship;
        });
      }
    } else {
      userInfo.update((val) {
        val?.nickname = friendInfo.nickname;
        val?.faceURL = friendInfo.faceURL;
        val?.remark = friendInfo.remark;
        val?.isBlacklist = isBlack;
        val?.isFriendship = isFriendship;
      });
      // FriendInfo.ex belongs to the friend relationship. The signature is in
      // the user's SDK profile extension, so read UserInfo for this field.
      try {
        final profiles = await OpenIM.iMManager.userManager
            .getUsersInfo(userIDList: [userID]);
        if (isClosed) return;
        final profile = profiles.firstOrNull;
        if (profile != null) userInfo.update((value) => value?.ex = profile.ex);
      } catch (_) {
        // Keep cached profile data if this optional refresh fails.
      }
    }
    UserCacheManager().addOrUpdateUserInfo(userID, userInfo.value);
    await _loadProfileGender(userID);
  }

  Future<void> _loadProfileGender(String userID) async {
    final request = ++_profileRequest;
    List<UserFullInfo>? profiles;
    try {
      profiles = await Apis.getUserFullInfo(userIDList: [userID]);
    } catch (_) {
      // Keep SDK information usable when the optional full profile is unavailable.
      return;
    }
    if (isClosed ||
        request != _profileRequest ||
        userInfo.value.userID != userID) return;
    final profile = profiles?.firstWhereOrNull((info) => info.userID == userID);
    if (profile == null) return;
    userInfo.update((value) {
      value?.account = profile.account;
      value?.gender = profile.gender;
      value?.allowAddFriend = profile.allowAddFriend;
    });
    UserCacheManager().addOrUpdateUserInfo(userID, userInfo.value);
  }

  void _resetAvatar(String url) async {
    clearMemoryImageCache(keyToMd5(url));
    await clearDiskCachedImage(url);
    PaintingBinding.instance.imageCache.evict(keyToMd5(url));
    userInfo.refresh();
  }

  void _syncGroupPrivacy() {
    final exempt = iHaveAdminOrOwnerPermission.value ||
        groupInfo?.ownerUserID == OpenIM.iMManager.userID;
    notAllowLookGroupMemberProfiles.value =
        !exempt && groupInfo?.lookMemberInfo == 1;
    notAllowAddGroupMemberFriend.value =
        !exempt && groupInfo?.applyMemberFriend == 1;
  }

  _queryGroupInfo() async {
    if (isGroupMemberPage) {
      var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
        groupIDList: [groupID!],
      );
      if (isClosed) return;
      groupInfo = list.firstOrNull;

      _syncGroupPrivacy();
    }
  }

  _queryGroupMemberInfo() async {
    if (isGroupMemberPage) {
      final list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupID: groupID!,
        userIDList: [
          userInfo.value.userID!,
          if (!isMyself) OpenIM.iMManager.userID
        ],
      );
      final other =
          list.firstWhereOrNull((e) => e.userID == userInfo.value.userID);
      if (isClosed) return;
      groupMembersInfo = other;
      groupUserNickname.value = other?.nickname ?? '';
      joinGroupTime.value = other?.joinTime ?? 0;

      _getJoinGroupMethod(other);

      hasAdminPermission.value = other?.roleLevel == GroupRoleLevel.admin;

      if (!isMyself) {
        var me =
            list.firstWhereOrNull((e) => e.userID == OpenIM.iMManager.userID);

        iAmOwner.value = me?.roleLevel == GroupRoleLevel.owner;

        iHasMutePermissions.value = me?.roleLevel == GroupRoleLevel.owner ||
            (me?.roleLevel == GroupRoleLevel.admin &&
                other?.roleLevel == GroupRoleLevel.member);

        iHaveAdminOrOwnerPermission.value =
            me?.roleLevel == GroupRoleLevel.owner ||
                me?.roleLevel == GroupRoleLevel.admin;
      }

      if (isMyself) {
        iHaveAdminOrOwnerPermission.value =
            other?.roleLevel == GroupRoleLevel.owner ||
                other?.roleLevel == GroupRoleLevel.admin;
      }
      _syncGroupPrivacy();

      if (null != other &&
          null != other.muteEndTime &&
          other.muteEndTime! > 0) {
        _calMuteTime(other.muteEndTime!);
      }
    }
  }

  _getJoinGroupMethod(GroupMembersInfo? other) async {
    if (other?.joinSource == 2) {
      if (other!.inviterUserID != null && other.inviterUserID != other.userID) {
        final list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
          groupID: groupID!,
          userIDList: [other.inviterUserID!],
        );
        var inviterUserInfo = list.firstOrNull;
        if (isClosed) return;
        inviterID.value = other.inviterUserID!;
        inviterName.value = inviterUserInfo?.nickname ?? other.inviterUserID!;
        joinGroupMethod.value = sprintf(
          StrRes.byInviteJoinGroup,
          [inviterUserInfo?.nickname ?? ''],
        );
      }
    } else if (other?.joinSource == 3) {
      joinGroupMethod.value = StrRes.byIDJoinGroup;
    } else if (other?.joinSource == 4) {
      joinGroupMethod.value = StrRes.byQrcodeJoinGroup;
    }
  }

  _calMuteTime(int time) {
    var date = DateUtil.formatDateMs(time, format: IMUtils.getTimeFormat2());
    var now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var diff = time - now;
    if (diff > 0) {
      mutedTime.value = date;
    } else {
      mutedTime.value = "";
    }
  }

  String getShowName() {
    if (isGroupMemberPage) {
      if (isFriendship) {
        if (null != IMUtils.emptyStrToNull(userInfo.value.remark)) {
          return '${groupUserNickname.value}(${IMUtils.emptyStrToNull(userInfo.value.remark)})';
        }
      }
      if (groupUserNickname.value.isEmpty) {
        return userInfo.value.nickname ??= "";
      }
      return groupUserNickname.value;
    }
    if (userInfo.value.remark != null && userInfo.value.remark!.isNotEmpty) {
      return '${userInfo.value.nickname}(${userInfo.value.remark})';
    }
    return userInfo.value.nickname ?? '';
  }

  void toChat() {
    conversationLogic.toChat(
      userID: userInfo.value.userID,
      nickname: userInfo.value.showName,
      faceURL: userInfo.value.faceURL,
    );
  }

  void toCall() {
    IMViews.openIMCallSheet(userInfo.value.showName, (index) {
      imLogic.call(
        callObj: CallObj.single,
        callType: index == 0 ? CallType.audio : CallType.video,
        inviteeUserIDList: [userInfo.value.userID!],
      );
    });
  }

  void callDirectly({required bool video}) {
    imLogic.call(
      callObj: CallObj.single,
      callType: video ? CallType.video : CallType.audio,
      inviteeUserIDList: [userInfo.value.userID!],
    );
  }

  Future<void> editRemark() async {
    final result = await AppNavigator.startSetFriendRemark();
    if (result is String) {
      userInfo.update((value) => value?.remark = result);
      UserCacheManager()
          .addOrUpdateUserInfo(userInfo.value.userID!, userInfo.value);
    }
  }

  final updatingBlacklist = false.obs;

  Future<void> setBlacklist(bool enabled) async {
    if (updatingBlacklist.value) return;
    updatingBlacklist.value = true;
    try {
      if (enabled) {
        final confirmed = await Get.dialog<bool>(
          CustomDialog(title: StrRes.areYouSureAddBlacklist),
        );
        if (confirmed != true) return;
      }
      await LoadingView.singleton.wrap(asyncFunction: () async {
        if (enabled) {
          await OpenIM.iMManager.friendshipManager
              .addBlacklist(userID: userInfo.value.userID!);
        } else {
          await OpenIM.iMManager.friendshipManager
              .removeBlacklist(userID: userInfo.value.userID!);
        }
      });
      if (isClosed) return;
      userInfo.update((value) => value?.isBlacklist = enabled);
      UserCacheManager()
          .addOrUpdateUserInfo(userInfo.value.userID!, userInfo.value);
    } catch (_) {
      IMViews.showToast(StrRes.saveFailed);
    } finally {
      if (!isClosed) updatingBlacklist.value = false;
    }
  }

  bool get showMemberIMID => false;

  String get displayedUserID => userInfo.value.account ?? '';

  void copyID() {
    if (displayedUserID.isNotEmpty) IMUtils.copy(text: displayedUserID);
  }

  void addFriend() => AppNavigator.startSendVerificationApplication(
        userID: userInfo.value.userID!,
        addSource: addSource == FriendAddSource.group &&
                iHaveAdminOrOwnerPermission.value
            ? FriendAddSource.manage
            : addSource,
        friendAddFields: friendAddFields,
        friendGroupID: groupID,
      );

  void viewInviter() {
    if (inviterID.value.isEmpty) return;
    AppNavigator.startUserProfilePane(
      userID: inviterID.value,
      nickname: inviterName.value,
      groupID: groupID,
    );
  }

  void viewPersonalInfo() => AppNavigator.startPersonalInfo(
        userID: userInfo.value.userID!,
      );

  void friendSetup() => AppNavigator.startFriendSetup(
        userID: userInfo.value.userID!,
      );
}

class UserCacheManager {
  static final UserCacheManager _instance = UserCacheManager._();
  UserCacheManager._();
  final Map<String, UserFullInfo> _userInfoMap = {};

  void addOrUpdateUserInfo(String userID, UserFullInfo userInfo) {
    _userInfoMap[userID] = userInfo;
  }

  UserFullInfo? getUserInfo(String userID) {
    return _userInfoMap[userID];
  }

  void removeUserInfo(String userID) {
    _userInfoMap.remove(userID);
  }

  factory UserCacheManager() {
    return _instance;
  }
}
