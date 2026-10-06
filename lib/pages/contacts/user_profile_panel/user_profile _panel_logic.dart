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
import '../../../core/session/session_request_errors.dart';
import '../../../services/common_group_count_service.dart';
import '../common_groups/common_groups_page.dart';
import '../../mine/settings/pages/chat_background_page.dart';
import '../../chat/chat_logic.dart';
import '../../chat/group_setup/group_manage/group_friend_protection_store.dart';
import 'adding/profile_friend_add_account_resolver.dart';
import 'identity/group_profile_account_state.dart';

class UserProfilePanelLogic extends GetxController with WidgetsBindingObserver {
  UserProfilePanelLogic({
    GroupProfileMembersLoader? groupMembersLoader,
    GroupFriendProtectionStore Function(String groupID)?
        friendProtectionFactory,
    ProfileFriendAddAccountResolver? friendAddAccountResolver,
    void Function(String)? friendAddNotify,
  })  : _groupMembersLoader = groupMembersLoader,
        _friendProtectionFactory = friendProtectionFactory,
        _friendAddAccountResolver =
            friendAddAccountResolver ?? ProfileFriendAddAccountResolver(),
        _friendAddNotify =
            friendAddNotify ?? ((message) => IMViews.showToast(message));

  final GroupProfileMembersLoader? _groupMembersLoader;
  final GroupFriendProtectionStore Function(String groupID)?
      _friendProtectionFactory;
  final ProfileFriendAddAccountResolver _friendAddAccountResolver;
  final void Function(String) _friendAddNotify;
  GroupFriendProtectionStore? _groupFriendProtection;
  Worker? _friendProtectionWorker;
  GroupProfileAccountState? _groupAccountState;
  int? _groupLookMemberInfo;
  int? _viewerRole;
  int? _viewerAppManagerLevel;
  int _groupPermissionEpoch = 0;
  int _groupInfoRead = 0;
  int _groupMembersRead = 0;
  final _groupContextClosed = false.obs;
  bool get hasActiveGroupMemberContext =>
      !isGroupMemberPage || !_groupContextClosed.value;
  Object get _groupPermissionScope => (
        _groupPermissionEpoch,
        groupID,
        DataSp.userID,
        OpenIM.iMManager.userID,
        DataSp.imToken,
        Config.imApiUrl,
      );
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
  int _userInfoRequest = 0;
  final profileLayoutReady = false.obs;
  final initialProfileFailed = false.obs;
  final commonGroupCount = RxnInt();
  final loadingCommonGroups = true.obs;
  final commonGroupsFailed = false.obs;
  final _commonGroupService = CommonGroupCountService();
  final _commonGroupSubscriptions = <StreamSubscription>[];
  final _groupIdentitySubscriptions = <StreamSubscription>[];
  Timer? _commonGroupRefreshTimer;
  int _commonGroupRequest = 0;
  CancelToken? _commonGroupCancel;
  late StreamSubscription _friendAddedSub;
  late StreamSubscription _friendDeletedSub;
  late StreamSubscription _friendInfoChangedSub;
  late StreamSubscription _memberInfoChangedSub;
  late StreamSubscription _groupInfoChangedSub;
  late StreamSubscription _selfInfoUpdatedSub;

  @override
  void onClose() {
    _friendAddAccountResolver.close();
    _groupPermissionEpoch++;
    _friendProtectionWorker?.dispose();
    _groupFriendProtection?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _groupAccountState?.close();
    _groupInfoChangedSub.cancel();
    _userInfoRequest++;
    _commonGroupRequest++;
    _commonGroupCancel?.cancel();
    _commonGroupRefreshTimer?.cancel();
    for (final subscription in _commonGroupSubscriptions) {
      subscription.cancel();
    }
    for (final subscription in _groupIdentitySubscriptions) {
      subscription.cancel();
    }
    if (Get.isRegistered<ContactsLogic>()) {
      Get.find<ContactsLogic>().setProfilePresence(this, null);
    }
    _friendAddedSub.cancel();
    _friendInfoChangedSub.cancel();
    _memberInfoChangedSub.cancel();
    _friendDeletedSub.cancel();
    _selfInfoUpdatedSub.cancel();
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
    if (isGroupMemberPage) {
      WidgetsBinding.instance.addObserver(this);
      _groupAccountState = GroupProfileAccountState(
        groupID: groupID!,
        userID: userInfo.value.userID!,
        load: _groupMembersLoader,
      );
      _groupFriendProtection = _friendProtectionFactory?.call(groupID!) ??
          GroupFriendProtectionStore(groupID!);
      _friendProtectionWorker = everAll([
        _groupFriendProtection!.protect,
        _groupFriendProtection!.ready,
      ], (_) => _syncGroupPrivacy());
    }
    friendAddFields =
        Map<String, String>.from(Get.arguments['friendAddFields'] ?? {});
    addSource =
        resolveFriendAddSource(Get.arguments['addSource'], groupID: groupID);
    offAllWhenDelFriend = Get.arguments['offAllWhenDelFriend'];
    forceCanAdd = Get.arguments['forceCanAdd'];

    // The live, session-owned directory knows a friend's layout before the
    // first frame. A cached UserFullInfo alone is not proof of friendship.
    if (isMyself) {
      profileLayoutReady.value = true;
    } else if (Get.isRegistered<ContactsLogic>()) {
      final contacts = Get.find<ContactsLogic>();
      final friend = !contacts.isCurrentSession
          ? null
          : contacts.friends.firstWhereOrNull(
              (value) => value.userID == userInfo.value.userID);
      if (friend != null) {
        userInfo.update((value) {
          value?.isFriendship = true;
          value?.nickname = friend.nickname ?? value.nickname;
          value?.faceURL = friend.faceURL ?? value.faceURL;
          value?.remark = friend.remark;
          value?.gender = friend.gender;
        });
        profileLayoutReady.value = true;
      }
    }

    // The directory and initial SDK read own the starting relationship.
    final friendAdds = imLogic.friendAddSubject;
    _friendAddedSub =
        friendAdds.skip(friendAdds.hasValue ? 1 : 0).listen((user) {
      if (user.userID == userInfo.value.userID) {
        _userInfoRequest++;
        userInfo.update((val) {
          val?.isFriendship = true;
        });
        profileLayoutReady.value = true;
        _loadProfileGender(user.userID!);
      }
    });

    final friendDeletes = imLogic.friendDelSubject;
    _friendDeletedSub =
        friendDeletes.skip(friendDeletes.hasValue ? 1 : 0).listen((user) {
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

    final selfInfoUpdates = imLogic.selfInfoUpdatedSubject;
    // onReady owns the first lookup; the subject may replay an older profile.
    _selfInfoUpdatedSub =
        selfInfoUpdates.skip(selfInfoUpdates.hasValue ? 1 : 0).listen((value) {
      if (isClosed ||
          !isGroupMemberPage ||
          _groupContextClosed.value ||
          value.userID?.isNotEmpty != true ||
          value.userID != OpenIM.iMManager.userID ||
          value.userID != DataSp.userID) {
        return;
      }
      _groupPermissionEpoch++;
      _refreshGroupAccount();
      unawaited(_groupFriendProtection?.refresh());
      unawaited(_queryGroupInfo());
      unawaited(_queryGroupMemberInfo());
    });

    _memberInfoChangedSub = imLogic.memberInfoChangedSubject.listen((value) {
      if (!isGroupMemberPage ||
          _groupContextClosed.value ||
          value.groupID != groupID) return;
      if (value.userID == OpenIM.iMManager.userID) {
        final roleChanged = _viewerRole != value.roleLevel ||
            _viewerAppManagerLevel != value.appManagerLevel;
        if (roleChanged) _groupPermissionEpoch++;
        _viewerRole = value.roleLevel;
        _viewerAppManagerLevel = value.appManagerLevel;
        iHaveAdminOrOwnerPermission.value =
            value.roleLevel == GroupRoleLevel.owner ||
                value.roleLevel == GroupRoleLevel.admin;
        iAmOwner.value = value.roleLevel == GroupRoleLevel.owner;
        _syncGroupPrivacy();
        if (roleChanged) {
          _refreshGroupAccount();
          if (groupInfo == null) unawaited(_queryGroupInfo());
        }
      }
      if (value.userID == userInfo.value.userID) {
        if (null != value.muteEndTime) {
          _calMuteTime(value.muteEndTime!);
        }
        groupUserNickname.value = value.nickname ?? '';
      }
    });
    _groupInfoChangedSub = imLogic.groupInfoUpdatedSubject.listen((value) {
      if (!isGroupMemberPage ||
          _groupContextClosed.value ||
          value.groupID != groupID) return;
      final privacyChanged = _groupLookMemberInfo != value.lookMemberInfo;
      if (privacyChanged) _groupPermissionEpoch++;
      _groupLookMemberInfo = value.lookMemberInfo;
      groupInfo = value;
      _syncGroupPrivacy();
      if (privacyChanged) {
        _refreshGroupAccount();
        unawaited(_queryGroupMemberInfo());
      }
    });
    if (isGroupMemberPage) {
      _groupIdentitySubscriptions.addAll([
        imLogic.joinedGroupDeletedSubject.listen((value) {
          if (value.groupID == groupID) {
            _groupContextClosed.value = true;
            _groupPermissionEpoch++;
            _groupAccountState?.close();
            _groupFriendProtection?.dispose();
          }
        }),
        imLogic.memberDeletedSubject.listen((value) {
          if (value.groupID == groupID &&
              (value.userID == OpenIM.iMManager.userID ||
                  value.userID == userInfo.value.userID)) {
            _groupContextClosed.value = true;
            _groupPermissionEpoch++;
            _groupAccountState?.close();
            _groupFriendProtection?.dispose();
          }
        }),
      ]);
    }
    super.onInit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        isGroupMemberPage &&
        !_groupContextClosed.value) {
      _groupPermissionEpoch++;
      _refreshGroupAccount();
      unawaited(_groupFriendProtection?.refresh());
      unawaited(_queryGroupInfo());
      unawaited(_queryGroupMemberInfo());
    }
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
    _refreshGroupAccount();
    unawaited(_groupFriendProtection?.refresh());
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
      final count = await _commonGroupService.count(userInfo.value.userID!,
          cancelToken: cancel);
      if (isClosed || request != _commonGroupRequest || DataSp.userID != owner)
        return;
      commonGroupCount.value = count;
    } catch (_) {
      if (isClosed || request != _commonGroupRequest || DataSp.userID != owner)
        return;
      commonGroupsFailed.value = true;
    } finally {
      if (!isClosed &&
          request == _commonGroupRequest &&
          DataSp.userID == owner) {
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

  Future<void> retryInitialProfile() => _getUsersInfo();

  Future<void> _getUsersInfo() async {
    final request = ++_userInfoRequest;
    final owner = DataSp.userID;
    final sdkOwner = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    bool stale() =>
        isClosed ||
        request != _userInfoRequest ||
        OpenIM.iMManager.userID != sdkOwner ||
        DataSp.userID != owner ||
        DataSp.chatToken != token;
    initialProfileFailed.value = false;
    try {
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
        if (stale()) return;

        userInfo.update((val) {
          val?.nickname = user.nickname;
          val?.faceURL = user.faceURL;
          val?.ex = user.ex;
        });

        UserCacheManager().addOrUpdateUserInfo(userID, userInfo.value);
        profileLayoutReady.value = true;
        await _loadProfileGender(userID);
        return;
      }

      final friendInfo =
          (await OpenIM.iMManager.friendshipManager.getFriendsInfo(
        userIDList: [userID],
      ))
              .firstOrNull;
      if (stale()) return;

      final blackList = await OpenIM.iMManager.friendshipManager.getBlacklist();
      if (stale()) return;

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
          if (stale()) return;
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
        profileLayoutReady.value = true;
        // FriendInfo.ex belongs to the friend relationship. The signature is in
        // the user's SDK profile extension, so read UserInfo for this field.
        try {
          final profiles = await OpenIM.iMManager.userManager
              .getUsersInfo(userIDList: [userID]);
          if (stale()) return;
          final profile = profiles.firstOrNull;
          if (profile != null) {
            userInfo.update((value) => value?.ex = profile.ex);
          }
        } catch (_) {
          // Keep cached profile data if this optional refresh fails.
        }
      }
      if (stale()) return;
      UserCacheManager().addOrUpdateUserInfo(userID, userInfo.value);
      await _loadProfileGender(userID);
      if (!stale()) profileLayoutReady.value = true;
    } catch (_) {
      if (!stale() && !profileLayoutReady.value) {
        initialProfileFailed.value = true;
      }
    }
  }

  Future<void> _loadProfileGender(String userID) async {
    final request = ++_profileRequest;
    final owner = DataSp.userID;
    final sdkOwner = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    List<UserFullInfo>? profiles;
    try {
      profiles = await Apis.getUserFullInfo(userIDList: [userID]);
    } catch (_) {
      // Keep SDK information usable when the optional full profile is unavailable.
      return;
    }
    if (isClosed ||
        request != _profileRequest ||
        OpenIM.iMManager.userID != sdkOwner ||
        DataSp.userID != owner ||
        DataSp.chatToken != token ||
        userInfo.value.userID != userID) {
      return;
    }
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
    final exempt = iHaveAdminOrOwnerPermission.value;
    notAllowLookGroupMemberProfiles.value =
        !exempt && groupInfo?.lookMemberInfo == 1;
    notAllowAddGroupMemberFriend.value = !exempt &&
        _groupFriendProtection?.ready.value == true &&
        _groupFriendProtection?.protect.value == true;
  }

  void _refreshGroupAccount() {
    if (isClosed || !isGroupMemberPage || _groupContextClosed.value) return;
    // Refresh clears the prior disclosure before issuing the current IM query.
    unawaited(_groupAccountState?.refresh());
  }

  Future<void> _queryGroupInfo() async {
    if (isGroupMemberPage && !_groupContextClosed.value) {
      final scope = _groupPermissionScope;
      final request = ++_groupInfoRead;
      final List<GroupInfo> list;
      try {
        list = await OpenIM.iMManager.groupManager.getGroupsInfo(
          groupIDList: [groupID!],
        );
      } catch (_) {
        return;
      }
      if (isClosed ||
          request != _groupInfoRead ||
          scope != _groupPermissionScope) {
        return;
      }
      groupInfo = list.firstWhereOrNull((value) => value.groupID == groupID);
      final privacyChanged = _groupLookMemberInfo != groupInfo?.lookMemberInfo;
      _groupLookMemberInfo = groupInfo?.lookMemberInfo;
      _syncGroupPrivacy();
      if (privacyChanged) _refreshGroupAccount();
    }
  }

  Future<void> _queryGroupMemberInfo() async {
    if (isGroupMemberPage && !_groupContextClosed.value) {
      final scope = _groupPermissionScope;
      final request = ++_groupMembersRead;
      final List<GroupMembersInfo> list;
      try {
        list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
          groupID: groupID!,
          userIDList: [
            userInfo.value.userID!,
            if (!isMyself) OpenIM.iMManager.userID
          ],
        );
      } catch (_) {
        return;
      }
      if (isClosed ||
          request != _groupMembersRead ||
          scope != _groupPermissionScope) {
        return;
      }
      final other =
          list.firstWhereOrNull((e) => e.userID == userInfo.value.userID);
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
      _viewerRole = isMyself
          ? other?.roleLevel
          : list
              .firstWhereOrNull((e) => e.userID == OpenIM.iMManager.userID)
              ?.roleLevel;
      _viewerAppManagerLevel = isMyself
          ? other?.appManagerLevel
          : list
              .firstWhereOrNull((e) => e.userID == OpenIM.iMManager.userID)
              ?.appManagerLevel;
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

  String get displayedUserID => isGroupMemberPage
      ? _groupAccountState?.value ?? ''
      : userInfo.value.account ?? '';

  void copyID() {
    if (displayedUserID.isNotEmpty) IMUtils.copy(text: displayedUserID);
  }

  FriendAddSource get friendAddRequestSource =>
      addSource == FriendAddSource.group && iHaveAdminOrOwnerPermission.value
          ? FriendAddSource.manage
          : addSource;

  bool get hasFriendAddEntry =>
      hasActiveGroupMemberContext &&
      FriendAddRequest.canSend(
        userID: userInfo.value.userID ?? '',
        source: friendAddRequestSource,
        groupID: groupID,
        fields: friendAddFields,
      );

  bool get canPrepareFriendAdd =>
      hasFriendAddEntry ||
      (addSource == FriendAddSource.chat &&
          !isGroupMemberPage &&
          normalizePublicAccountSearch(displayedUserID) != null);

  final preparingFriendAdd = false.obs;

  bool get _canAddFriendFromProfile =>
      !isMyself &&
      !isFriendship &&
      !userInfo.value.isBlacklist &&
      hasActiveGroupMemberContext &&
      ((isGroupMemberPage &&
              (iAmOwner.value || iHaveAdminOrOwnerPermission.value)) ||
          (isAllowAddFriend &&
              (!isGroupMemberPage ||
                  forceCanAdd == true ||
                  !notAllowAddGroupMemberFriend.value)));

  void addFriend() {
    if (isClosed ||
        preparingFriendAdd.value ||
        !_friendAddAccountResolver.isCurrentSession ||
        !_canAddFriendFromProfile) {
      return;
    }
    unawaited(_openFriendApplication());
  }

  Future<void> _openFriendApplication() async {
    final targetID = userInfo.value.userID ?? '';
    if (targetID.isEmpty) return;
    final account = displayedUserID;
    final source = friendAddRequestSource;
    final fields = Map<String, String>.from(friendAddFields);
    final friendGroup = groupID;
    final permissionEpoch = _groupPermissionEpoch;
    final sdkOwner = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    final profileRoute = Get.currentRoute;
    final profileArguments = Get.arguments;
    bool active() =>
        !isClosed &&
        Get.currentRoute == profileRoute &&
        identical(Get.arguments, profileArguments) &&
        _friendAddAccountResolver.isCurrentSession &&
        targetID == userInfo.value.userID &&
        friendGroup == groupID &&
        permissionEpoch == _groupPermissionEpoch &&
        source == friendAddRequestSource &&
        _canAddFriendFromProfile &&
        (source != FriendAddSource.chat || account == displayedUserID);

    preparingFriendAdd.value = true;
    try {
      var effectiveSource = source;
      var entryFields = fields;
      if (!FriendAddRequest.canSend(
        userID: targetID,
        source: source,
        groupID: friendGroup,
        fields: fields,
      )) {
        if (source != FriendAddSource.chat || isGroupMemberPage) {
          throw const ProfileFriendAddUnavailable(
              ProfileFriendAddUnavailableReason.missingAccount);
        }
        final verifiedAccount = await _friendAddAccountResolver.resolve(
          userID: targetID,
          account: account,
        );
        if (verifiedAccount == null || !active()) return;
        effectiveSource = FriendAddSource.account;
        entryFields = {'account': verifiedAccount};
      }
      if (!active()) return;
      await AppNavigator.startSendVerificationApplication(
        userID: targetID,
        targetName: userInfo.value.nickname,
        targetAvatarURL: userInfo.value.faceURL,
        targetAccount: entryFields['account'] ?? account,
        selfNickname: imLogic.userInfo.value.nickname,
        addSource: effectiveSource,
        friendAddFields: entryFields,
        friendGroupID: friendGroup,
      );
    } catch (error) {
      if (!active()) return;
      final chinese = Get.locale?.languageCode != 'en';
      if (error is ProfileFriendAddUnavailable) {
        _friendAddNotify(error.reason ==
                ProfileFriendAddUnavailableReason.missingAccount
            ? (chinese
                ? '对方未公开聊天号，请让对方分享二维码或名片。'
                : 'Ask this person to share a QR code or contact card.')
            : (chinese
                ? '暂时无法通过该聊天号添加，请让对方分享二维码或名片。'
                : 'This account cannot be used to add the person. Ask for a QR code or contact card.'));
      } else if (!handleSessionAuthFailure(error,
          account: sdkOwner, token: token)) {
        _friendAddNotify(friendAddErrorMessage(error, chinese: chinese) ??
            (chinese
                ? '暂时无法添加好友，请稍后重试'
                : 'Unable to add this person. Please try again later.'));
      }
    } finally {
      if (!isClosed) preparingFriendAdd.value = false;
    }
  }

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
