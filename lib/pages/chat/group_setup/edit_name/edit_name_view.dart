import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'edit_name_logic.dart';
import '../../../contacts/user_profile_panel/set_remark/set_remark_view.dart';

class EditGroupNamePage extends StatelessWidget {
  final logic = Get.find<EditGroupNameLogic>();

  EditGroupNamePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isGroupName = logic.type == EditNameType.groupNickname;
    return Obx(() => SetFriendRemarkPage.editor(
          controller: logic.inputCtrl,
          avatarURL: isGroupName
              ? logic.groupSetupLogic.groupInfo.value.faceURL ?? logic.faceUrl
              : logic.groupSetupLogic.myGroupMembersInfo.value.faceURL ??
                  logic.groupSetupLogic.imLogic.userInfo.value.faceURL,
          avatarName: isGroupName
              ? logic.groupSetupLogic.groupInfo.value.groupName
              : logic.groupSetupLogic.imLogic.userInfo.value.nickname,
          isGroupAvatar: isGroupName,
          maxLength: 30,
          onSave: logic.save,
          onAvatarTap:
              isGroupName ? logic.groupSetupLogic.modifyGroupAvatar : null,
        ));
  }
}
