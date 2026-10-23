import '../../../channels/models/channel_kind.dart';
import 'package:openim_common/localization.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'group_member_permissions_page.dart';
import 'group_friend_protection_store.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../routes/app_navigator.dart';
import '../group_member_list/group_member_list_logic.dart';

class GroupManageLogic extends GetxController {
  final groupSetupLogic = Get.find<GroupSetupLogic>();

  Rx<GroupInfo> get groupInfo => groupSetupLogic.groupInfo;

  final busy = false.obs;
  bool _closed = false;
  late final friendProtection =
      GroupFriendProtectionStore(groupInfo.value.groupID);

  @override
  void onInit() {
    super.onInit();
    friendProtection.refresh();
  }

  @override
  void onClose() {
    _closed = true;
    friendProtection.dispose();
    super.onClose();
  }

  Future<void> saveRules(
      {bool? muted, int? verification, int? look, int? addFriend}) async {
    final context = groupSetupLogic.capturePermissionContext();
    bool isCurrent() =>
        !_closed &&
        !isClosed &&
        groupSetupLogic.isPermissionContextCurrent(context);
    final canSave = muted != null ||
            (verification != null && look == null && addFriend == null)
        ? groupSetupLogic.isOwnerOrAdmin
        : groupSetupLogic.isOwner;
    if (busy.value || !isCurrent() || !canSave) return;
    busy.value = true;
    try {
      final id = context.groupID;
      if (muted == false && isChannelEx(groupInfo.value.ex)) return;
      if (muted != null) {
        await OpenIM.iMManager.groupManager
            .changeGroupMute(groupID: id, mute: muted);
      } else {
        await OpenIM.iMManager.groupManager.setGroupInfo(GroupInfo(
            groupID: id,
            needVerification: verification,
            lookMemberInfo: look,
            applyMemberFriend: addFriend));
      }
      if (!isCurrent()) return;
      final groups =
          await OpenIM.iMManager.groupManager.getGroupsInfo(groupIDList: [id]);
      if (!isCurrent()) return;
      final group = groups.firstWhereOrNull((info) => info.groupID == id);
      if (group != null) {
        groupSetupLogic.applyGroupInfo(group);
        groupSetupLogic.imLogic.groupInfoUpdatedSubject.add(group);
      }
    } catch (error) {
      if (isCurrent()) IMViews.showErrorToast(error);
    } finally {
      if (!_closed && !isClosed) busy.value = false;
    }
  }

  Future<void> setMemberPrivacy(bool protect) async {
    final context = groupSetupLogic.capturePermissionContext();
    bool current() =>
        !_closed &&
        !isClosed &&
        groupSetupLogic.isPermissionContextCurrent(context);
    if (!current() ||
        busy.value ||
        friendProtection.busy.value ||
        !groupSetupLogic.isOwner ||
        !friendProtection.canManage.value ||
        !friendProtection.ready.value) {
      return;
    }
    busy.value = true;
    try {
      await friendProtection.setProtected(protect);
      if (!current()) return;
      if (!friendProtection.ready.value ||
          friendProtection.protect.value != protect) {
        return;
      }
      await OpenIM.iMManager.groupManager.setGroupInfo(
          GroupInfo(groupID: context.groupID, lookMemberInfo: protect ? 1 : 0));
      if (!current()) return;
      GroupInfo? group;
      // SetGroupInfo completes before the native group cache synchronizes.
      // Allow that bounded sync window before treating old cached data as a
      // failed write. Every await still fences account/role changes.
      for (var attempt = 0; attempt < 5; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          if (!current()) return;
        }
        final groups = await OpenIM.iMManager.groupManager
            .getGroupsInfo(groupIDList: [context.groupID]);
        if (!current()) return;
        group = groups.firstWhereOrNull((g) => g.groupID == context.groupID);
        if (group?.lookMemberInfo == (protect ? 1 : 0)) break;
      }
      if (group == null || group.lookMemberInfo != (protect ? 1 : 0)) {
        throw StateError('群成员隐私设置未完成，请重试');
      }
      groupSetupLogic.applyGroupInfo(group);
      groupSetupLogic.imLogic.groupInfoUpdatedSubject.add(group);
    } catch (_) {
      if (current()) {
        await groupSetupLogic.getGroupInfo();
        if (current()) IMViews.showToast(AppCopy.text('群成员隐私设置未完成，请重试'));
      }
    } finally {
      if (!_closed && !isClosed) busy.value = false;
    }
  }

  void admins() => Get.to(() => GroupMemberPermissionsPage(
      groupID: groupInfo.value.groupID,
      isChannel: isChannelEx(groupInfo.value.ex),
      owner: groupSetupLogic.isOwner,
      mode: MemberPermissionMode.admins));

  void mutedMembers() => Get.to(() => GroupMemberPermissionsPage(
      groupID: groupInfo.value.groupID,
      isChannel: isChannelEx(groupInfo.value.ex),
      owner: groupSetupLogic.isOwner,
      mode: MemberPermissionMode.muted));

  void transferGroupOwnerRight() async {
    var result = await AppNavigator.startGroupMemberList(
      groupInfo: groupInfo.value,
      opType: GroupMemberOpType.transferRight,
    );
    if (result is GroupMembersInfo) {
      await LoadingView.singleton.wrap(
        asyncFunction: () => OpenIM.iMManager.groupManager.transferGroupOwner(
          groupID: groupInfo.value.groupID,
          userID: result.userID!,
        ),
      );
      groupInfo.update((val) {
        val?.ownerUserID = result.userID;
      });
      Get.back();
    }
  }
}
