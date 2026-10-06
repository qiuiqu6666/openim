import 'group_member_order.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:synchronized/synchronized.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../core/controller/app_controller.dart';
import '../../../core/controller/im_controller.dart';
import '../../../routes/app_navigator.dart';
import '../../../services/chat_history_cache.dart';
import '../../contacts/select_contacts/select_contacts_logic.dart';
import '../../conversation/conversation_logic.dart';
import '../chat_logic.dart';
import '../chat_setup/chat_history_search_page.dart';
import 'edit_name/edit_name_logic.dart';
import 'group_member_list/group_member_list_logic.dart';
import '../group/identity/group_member_identity.dart';
import 'members/group_member_preview_controller.dart';

typedef GroupSetupPermissionContext = ({
  String? account,
  String sdkAccount,
  String? token,
  String server,
  String groupID,
  int generation,
});

class GroupSetupLogic extends GetxController {
  GroupSetupLogic({GroupMemberIdentitySource? memberIdentitySource})
      : _memberPreview = GroupMemberPreviewController(
          source: memberIdentitySource ?? GroupMemberIdentitySource(),
        );

  final GroupMemberPreviewController _memberPreview;
  int _groupInfoRequest = 0;
  int _myMemberRequest = 0;
  int _joinedRequest = 0;
  int _permissionGeneration = 0;
  bool _closed = false;
  late final GroupSetupPermissionContext _initialPermissionContext;
  int? _memberLookMemberInfo;
  bool _hasGroupInfo = false;
  final imLogic = Get.find<IMController>();

  final chatLogic = Get.find<ChatLogic>(tag: GetTags.chat);
  final appLogic = Get.find<AppController>();
  final conversationLogic = Get.find<ConversationLogic>();
  RxList<GroupMembersInfo> get memberList => _memberPreview.members;
  RxBool get membersLoading => _memberPreview.loading;
  RxBool get membersFailed => _memberPreview.failed;
  late Rx<ConversationInfo> conversationInfo;
  late Rx<GroupInfo> groupInfo;
  late Rx<GroupMembersInfo> myGroupMembersInfo;
  late StreamSubscription _guSub;
  late StreamSubscription _mASub;
  late StreamSubscription _mISub;
  late StreamSubscription _mDSub;
  late StreamSubscription _ccSub;
  late StreamSubscription _jasSub;
  late StreamSubscription _jdsSub;
  StreamSubscription? _selfInfoSubscription;
  final lock = Lock();
  final isJoinedGroup = false.obs;
  final avatar = Rx<File?>(null);

  @override
  void onInit() async {
    if (Get.arguments['conversationInfo'] != null) {
      conversationInfo = Rx(Get.arguments['conversationInfo']);
    } else {
      final temp = await OpenIM.iMManager.conversationManager
          .getOneConversation(
              sourceID: chatLogic.conversationInfo.isGroupChat
                  ? chatLogic.conversationInfo.groupID!
                  : chatLogic.conversationInfo.userID!,
              sessionType: chatLogic.conversationInfo.conversationType!);
      conversationInfo = Rx(temp);
    }
    groupInfo = Rx(_defaultGroupInfo);
    myGroupMembersInfo = Rx(_defaultMemberInfo);
    _initialPermissionContext = capturePermissionContext();

    _ccSub = imLogic.conversationChangedSubject.listen((newList) {
      final newValue = newList.firstWhereOrNull((element) =>
          element.conversationID == conversationInfo.value.conversationID);
      if (newValue != null) {
        conversationInfo.update((val) {
          val?.isPinned = newValue.isPinned;

          val?.recvMsgOpt = newValue.recvMsgOpt;
          val?.isMsgDestruct = newValue.isMsgDestruct;
          val?.msgDestructTime = newValue.msgDestructTime;
        });
      }
    });

    _guSub = imLogic.groupInfoUpdatedSubject.listen((value) {
      if (_isCurrentGroupSession && value.groupID == groupInfo.value.groupID) {
        applyGroupInfo(value);
      }
    });

    final selfInfo = imLogic.selfInfoUpdatedSubject;
    _selfInfoSubscription = (selfInfo.hasValue ? selfInfo.skip(1) : selfInfo)
        .listen(onSelfInfoUpdated);

    _jasSub = imLogic.joinedGroupAddedSubject.listen((value) {
      if (_isCurrentGroupSession && value.groupID == groupInfo.value.groupID) {
        _joinedRequest++;
        _permissionGeneration++;
        isJoinedGroup.value = true;
        _queryAllInfo();
      }
    });

    _jdsSub = imLogic.joinedGroupDeletedSubject.listen((value) {
      if (_isCurrentGroupSession && value.groupID == groupInfo.value.groupID) {
        _leaveGroup();
      }
    });

    _mISub = imLogic.memberInfoChangedSubject.listen((e) {
      if (!_isCurrentGroupSession) return;
      if (e.groupID == groupInfo.value.groupID &&
          e.userID == myGroupMembersInfo.value.userID) {
        final permissionChanged = (e.roleLevel != null &&
                myGroupMembersInfo.value.roleLevel != e.roleLevel) ||
            (e.appManagerLevel != null &&
                myGroupMembersInfo.value.appManagerLevel != e.appManagerLevel);
        if (permissionChanged) _permissionGeneration++;
        myGroupMembersInfo.update((val) {
          val?.nickname = e.nickname;
          if (e.roleLevel != null) val?.roleLevel = e.roleLevel;
          if (e.appManagerLevel != null) {
            val?.appManagerLevel = e.appManagerLevel;
          }
        });
        if (permissionChanged) _refreshMemberIdentity();
      }
      if (!isJoinedGroup.value || e.groupID != groupInfo.value.groupID) return;
      final index = memberList.indexWhere((m) => m.userID == e.userID);
      if (index >= 0) {
        memberList[index] = e;
      } else if (e.roleLevel == GroupRoleLevel.owner ||
          e.roleLevel == GroupRoleLevel.admin) {
        memberList.add(e);
      }
      memberList.sort(compareGroupMembers);
    });
    _mASub = imLogic.memberAddedSubject.listen((e) async {
      if (_isCurrentGroupSession && e.groupID == groupInfo.value.groupID) {
        if (e.userID == OpenIM.iMManager.userID) {
          _joinedRequest++;
          _permissionGeneration++;
          isJoinedGroup.value = true;
          _queryAllInfo();
        } else {
          memberList.add(e);
          memberList.sort(compareGroupMembers);
        }
      }
    });
    _mDSub = imLogic.memberDeletedSubject.listen((e) {
      if (_isCurrentGroupSession && e.groupID == groupInfo.value.groupID) {
        if (e.userID == OpenIM.iMManager.userID) {
          _leaveGroup();
        } else {
          memberList.removeWhere((element) => element.userID == e.userID);
        }
      }
    });
    super.onInit();
  }

  @override
  void onReady() {
    _checkIsJoinedGroup();
    super.onReady();
  }

  @override
  void onClose() {
    _closed = true;
    _permissionGeneration++;
    _joinedRequest++;
    _memberPreview.dispose();
    _guSub.cancel();
    _mASub.cancel();
    _mDSub.cancel();
    _ccSub.cancel();
    _mISub.cancel();
    _jdsSub.cancel();
    _jasSub.cancel();
    _selfInfoSubscription?.cancel();
    super.onClose();
  }

  void onSelfInfoUpdated(UserInfo value) {
    if (!_isCurrentGroupSession || value.userID != OpenIM.iMManager.userID) {
      return;
    }
    _permissionGeneration++;
    _memberPreview.invalidate();
    _queryAllInfo();
  }

  get _defaultGroupInfo => GroupInfo(
        groupID: conversationInfo.value.groupID!,
        groupName: conversationInfo.value.showName,
        faceURL: conversationInfo.value.faceURL,
        memberCount: 0,
      );

  get _defaultMemberInfo => GroupMembersInfo(
        userID: OpenIM.iMManager.userID,
        nickname: OpenIM.iMManager.userInfo.nickname,
      );

  bool get isOwnerOrAdmin => isOwner || isAdmin;

  bool get isAdmin =>
      myGroupMembersInfo.value.roleLevel == GroupRoleLevel.admin;

  bool get isNotDisturb => conversationInfo.value.recvMsgOpt == 2;

  bool get isPinned => conversationInfo.value.isPinned == true;
  String? get myGroupNickname {
    final nickname = myGroupMembersInfo.value.nickname?.trim();
    if (nickname == null ||
        nickname.isEmpty ||
        nickname == OpenIM.iMManager.userInfo.nickname) {
      return null;
    }
    return nickname;
  }

  final updating = false.obs;

  Future<void> setPinned(bool value) async {
    if (updating.value) return;
    updating.value = true;
    try {
      await conversationLogic.setPinned(conversationInfo.value, value);
      conversationInfo.refresh();
    } finally {
      updating.value = false;
    }
  }

  Future<void> setMuted(bool value) async {
    if (updating.value) return;
    updating.value = true;
    try {
      await conversationLogic.setNotDisturb(conversationInfo.value, value);
      conversationInfo.refresh();
    } finally {
      updating.value = false;
    }
  }

  void searchHistory() => Get.to(() =>
      ChatHistorySearchPage(conversationID: conversationID, isGroup: true));

  void editMyGroupNickname() =>
      AppNavigator.startEditGroupName(type: EditNameType.myGroupMemberNickname);

  bool get isOwner =>
      groupInfo.value.ownerUserID == OpenIM.iMManager.userID ||
      myGroupMembersInfo.value.roleLevel == GroupRoleLevel.owner;

  String get conversationID => conversationInfo.value.conversationID;

  GroupSetupPermissionContext capturePermissionContext() => (
        account: DataSp.userID,
        sdkAccount: OpenIM.iMManager.userID,
        token: DataSp.imToken,
        server: Config.imApiUrl,
        groupID: groupInfo.value.groupID,
        generation: _permissionGeneration,
      );

  bool get _isCurrentGroupSession =>
      _isGroupContextCurrent(_initialPermissionContext);

  bool _isGroupContextCurrent(GroupSetupPermissionContext context) =>
      !_closed &&
      !isClosed &&
      context.groupID == groupInfo.value.groupID &&
      context.groupID == _initialPermissionContext.groupID &&
      context.account == _initialPermissionContext.account &&
      context.sdkAccount == _initialPermissionContext.sdkAccount &&
      context.token == _initialPermissionContext.token &&
      context.server == _initialPermissionContext.server &&
      context.account == DataSp.userID &&
      context.sdkAccount == OpenIM.iMManager.userID &&
      context.token == DataSp.imToken &&
      context.server == Config.imApiUrl;

  bool isPermissionContextCurrent(GroupSetupPermissionContext context) =>
      _isGroupContextCurrent(context) &&
      context.generation == _permissionGeneration &&
      isJoinedGroup.value;

  void _leaveGroup() {
    _joinedRequest++;
    _permissionGeneration++;
    isJoinedGroup.value = false;
    _memberPreview.invalidate();
  }

  void _checkIsJoinedGroup() async {
    final request = ++_joinedRequest;
    final context = capturePermissionContext();
    if (!_isGroupContextCurrent(context)) return;
    try {
      final joined = await OpenIM.iMManager.groupManager.isJoinedGroup(
        groupID: context.groupID,
      );
      if (request != _joinedRequest || !_isGroupContextCurrent(context)) return;
      isJoinedGroup.value = joined;
      _queryAllInfo();
    } catch (_) {
      // Leave membership unchanged when the SDK check is unavailable.
    }
  }

  void _queryAllInfo() {
    if (_isCurrentGroupSession && isJoinedGroup.value) {
      getGroupInfo();
      getGroupMembers();
      getMyGroupMemberInfo();
    }
  }

  Future<void> getGroupMembers() {
    final context = capturePermissionContext();
    return _memberPreview.refresh(
      groupID: context.groupID,
      scope: context,
      isCurrent: () => isPermissionContextCurrent(context),
    );
  }

  void _refreshMemberIdentity() {
    _memberPreview.invalidate();
    if (_isCurrentGroupSession && isJoinedGroup.value) {
      unawaited(getGroupMembers());
    }
  }

  Future<void> getGroupInfo() async {
    final request = ++_groupInfoRequest;
    final context = capturePermissionContext();
    if (!isPermissionContextCurrent(context)) return;
    try {
      final list = await OpenIM.iMManager.groupManager.getGroupsInfo(
        groupIDList: [context.groupID],
      );
      if (request != _groupInfoRequest ||
          !isPermissionContextCurrent(context)) {
        return;
      }
      final value =
          list.firstWhereOrNull((info) => info.groupID == context.groupID);
      if (null != value) {
        // A first group read must not invalidate the concurrent role read.
        _applyGroupInfo(value, externalEvent: false);
      }
    } catch (_) {
      // Optional metadata failures must not replace the latest group event.
    }
  }

  Future<void> getMyGroupMemberInfo() async {
    final request = ++_myMemberRequest;
    final context = capturePermissionContext();
    if (!isPermissionContextCurrent(context)) return;
    try {
      final list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupID: context.groupID,
        userIDList: [context.sdkAccount],
      );
      if (request != _myMemberRequest || !isPermissionContextCurrent(context)) {
        return;
      }
      final info = list.firstWhereOrNull((member) =>
          member.groupID == context.groupID &&
          member.userID == context.sdkAccount);
      if (null != info) {
        final firstRoleRead = myGroupMembersInfo.value.roleLevel == null &&
            myGroupMembersInfo.value.appManagerLevel == null;
        final permissionChanged = myGroupMembersInfo.value.roleLevel !=
                info.roleLevel ||
            myGroupMembersInfo.value.appManagerLevel != info.appManagerLevel;
        myGroupMembersInfo.update((val) {
          val?.nickname = info.nickname;
          val?.roleLevel = info.roleLevel;
          val?.appManagerLevel = info.appManagerLevel;
        });
        if (permissionChanged && !firstRoleRead) _refreshMemberIdentity();
      }
    } catch (_) {
      // Preserve event-confirmed permissions, including after leaving/closing.
    }
  }

  void applyGroupInfo(GroupInfo value) =>
      _applyGroupInfo(value, externalEvent: true);

  void _applyGroupInfo(GroupInfo value, {required bool externalEvent}) {
    if (!_isCurrentGroupSession || value.groupID != groupInfo.value.groupID) {
      return;
    }
    final firstMetadataRead = !_hasGroupInfo && !externalEvent;
    _hasGroupInfo = true;
    final privacyChanged = _memberLookMemberInfo != value.lookMemberInfo;
    final ownerChanged = groupInfo.value.ownerUserID != value.ownerUserID;
    if (externalEvent && (privacyChanged || ownerChanged)) {
      _permissionGeneration++;
    }
    _memberLookMemberInfo = value.lookMemberInfo;
    groupInfo.update((val) {
      val?.groupName = value.groupName;
      val?.faceURL = value.faceURL;
      val?.notification = value.notification;
      val?.introduction = value.introduction;
      val?.memberCount = value.memberCount;
      val?.ownerUserID = value.ownerUserID;
      val?.status = value.status;
      val?.needVerification = value.needVerification;
      val?.groupType = value.groupType;
      val?.lookMemberInfo = value.lookMemberInfo;
      val?.applyMemberFriend = value.applyMemberFriend;
      val?.notificationUserID = value.notificationUserID;
      val?.notificationUpdateTime = value.notificationUpdateTime;
      val?.ex = value.ex;
    });
    if (!firstMetadataRead && (privacyChanged || ownerChanged)) {
      _refreshMemberIdentity();
    }
    if (externalEvent &&
        (privacyChanged || ownerChanged) &&
        isJoinedGroup.value) {
      unawaited(getMyGroupMemberInfo());
    }
  }

  void modifyGroupAvatar() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      Get.context!,
      pickerConfig:
          const AssetPickerConfig(maxAssets: 1, requestType: RequestType.image),
    );
    if (assets != null) {
      final file = await assets.first.file;
      final result = await IMViews.uCropPic(file!.path);

      final path = result['path'];
      final url = result['url'];

      if (url != null) {
        avatar.value = File(path);
        await _modifyGroupInfo(faceUrl: url);
        groupInfo.update((val) {
          val?.faceURL = url;
        });
      }
    }
  }

  void modifyGroupName(String? faceUrl) => AppNavigator.startEditGroupName(
        type: EditNameType.groupNickname,
        faceUrl: faceUrl,
      );

  _modifyGroupInfo({
    String? groupName,
    String? notification,
    String? introduction,
    String? faceUrl,
  }) =>
      OpenIM.iMManager.groupManager.setGroupInfo(GroupInfo(
        groupID: groupInfo.value.groupID,
        groupName: groupName,
        notification: notification,
        introduction: introduction,
        faceURL: faceUrl,
      ));

  void viewGroupQrcode() => AppNavigator.startGroupQrcode();

  void viewGroupMembers() => AppNavigator.startGroupMemberList(
        groupInfo: groupInfo.value,
      );

  void groupManage() => AppNavigator.startGroupManage(
        groupInfo: groupInfo.value,
      );

  Future<void> _removeConversation() async {
    final conversationID = conversationInfo.value.conversationID;
    final accountID = OpenIM.iMManager.userID;
    await OpenIM.iMManager.conversationManager
        .deleteConversationAndDeleteAllMsg(
      conversationID: conversationID,
    );
    if (!chatLogic.isClosed &&
        chatLogic.conversationInfo.conversationID == conversationID) {
      chatLogic.clearAllMessage();
    }
    ChatHistoryCache.removeConversation(accountID, conversationID);
  }

  void quitGroup() async {
    if (isJoinedGroup.value) {
      if (isOwner) {
        var confirm = await Get.dialog(CustomDialog(
          title: StrRes.dismissGroupHint,
        ));
        if (confirm == true) {
          await OpenIM.iMManager.groupManager.dismissGroup(
            groupID: groupInfo.value.groupID,
          );
        } else {
          return;
        }
      } else {
        var confirm = await Get.dialog(CustomDialog(
          title: StrRes.quitGroupHint,
        ));
        if (confirm == true) {
          await OpenIM.iMManager.groupManager.quitGroup(
            groupID: groupInfo.value.groupID,
          );
        } else {
          return;
        }
      }
    } else {
      await _removeConversation();
    }

    AppNavigator.startBackMain();
  }

  void copyGroupID() {
    IMUtils.copy(text: groupInfo.value.groupID);
  }

  int length() {
    int buttons = isOwnerOrAdmin ? 2 : 1;
    return (memberList.length + buttons) > 10
        ? 10
        : (memberList.length + buttons);
  }

  Widget itemBuilder({
    required int index,
    required Widget Function(GroupMembersInfo info) builder,
    required Widget Function() addButton,
    required Widget Function() delButton,
  }) {
    var length = isOwnerOrAdmin ? 8 : 9;
    if (memberList.length > length) {
      if (index < length) {
        var info = memberList.elementAt(index);
        return builder(info);
      } else if (index == length) {
        return addButton();
      } else {
        return delButton();
      }
    } else {
      if (index < memberList.length) {
        var info = memberList.elementAt(index);
        return builder(info);
      } else if (index == memberList.length) {
        return addButton();
      } else {
        return delButton();
      }
    }
  }

  addMember() async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.addMember,
      groupID: groupInfo.value.groupID,
    );

    final list = IMUtils.convertSelectContactsResultToUserID(result);
    if (list is List<String>) {
      try {
        await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.groupManager.inviteUserToGroup(
            groupID: groupInfo.value.groupID,
            userIDList: list,
            reason: 'Come on baby',
          ),
        );
      } catch (_) {}
      getGroupMembers();
    }
  }

  removeMember() async {
    final list = await AppNavigator.startGroupMemberList(
      groupInfo: groupInfo.value,
      opType: GroupMemberOpType.del,
    );
    if (list is List<GroupMembersInfo>) {
      var removeUidList = list.map((e) => e.userID!).toList();
      try {
        await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.groupManager.kickGroupMember(
            groupID: groupInfo.value.groupID,
            userIDList: removeUidList,
            reason: 'Get out baby',
          ),
        );
      } catch (_) {}
      getGroupMembers();
    }
  }

  void viewMemberInfo(GroupMembersInfo membersInfo) =>
      AppNavigator.startUserProfilePane(
        userID: membersInfo.userID!,
        nickname: membersInfo.nickname,
        faceURL: membersInfo.faceURL,
        groupID: membersInfo.groupID,
      );
}
