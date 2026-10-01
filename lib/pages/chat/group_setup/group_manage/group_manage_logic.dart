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
  late final friendProtection =
      GroupFriendProtectionStore(groupInfo.value.groupID);

  @override
  void onInit() {
    super.onInit();
    friendProtection.refresh();
  }

  @override
  void onClose() {
    friendProtection.dispose();
    super.onClose();
  }

  Future<void> saveRules(
      {bool? muted, int? verification, int? look, int? addFriend}) async {
    if (busy.value || !groupSetupLogic.isOwner) return;
    busy.value = true;
    try {
      final id = groupInfo.value.groupID;
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
      final groups =
          await OpenIM.iMManager.groupManager.getGroupsInfo(groupIDList: [id]);
      if (!isClosed && groups.isNotEmpty) groupInfo.value = groups.first;
    } catch (error) {
      IMViews.showToast(error.toString());
    } finally {
      if (!isClosed) busy.value = false;
    }
  }

  void admins() => Get.to(() => GroupMemberPermissionsPage(
      groupID: groupInfo.value.groupID,
      owner: groupSetupLogic.isOwner,
      mode: MemberPermissionMode.admins));

  void mutedMembers() => Get.to(() => GroupMemberPermissionsPage(
      groupID: groupInfo.value.groupID,
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
