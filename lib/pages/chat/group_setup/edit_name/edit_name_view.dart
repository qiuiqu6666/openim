import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'edit_name_logic.dart';
import '../../../contacts/user_profile_panel/set_remark/set_remark_view.dart';

class EditGroupNamePage extends StatelessWidget {
  final logic = Get.find<EditGroupNameLogic>();

  EditGroupNamePage({super.key});

  String? get _groupAvatarUrl =>
      (logic.groupSetupLogic.groupInfo.value.faceURL ?? logic.faceUrl)?.trim();

  Future<void> _showAvatarActions(BuildContext context) => AvatarActions.open(
        context,
        url: _groupAvatarUrl,
        onChange: logic.groupSetupLogic.modifyGroupAvatar,
        isActive: () => !logic.isClosed && !logic.saving.value,
      );

  @override
  Widget build(BuildContext context) {
    final isGroupName = logic.type == EditNameType.groupNickname;
    return Obx(() => SetFriendRemarkPage.editor(
          controller: logic.inputCtrl,
          avatarURL: isGroupName
              ? _groupAvatarUrl
              : logic.groupSetupLogic.myGroupMembersInfo.value.faceURL ??
                  logic.groupSetupLogic.imLogic.userInfo.value.faceURL,
          avatarName: isGroupName
              ? logic.groupSetupLogic.groupInfo.value.groupName
              : logic.groupSetupLogic.imLogic.userInfo.value.nickname,
          isGroupAvatar: isGroupName,
          maxLength: 30,
          showClearButton: true,
          hintText: isGroupName
              ? null
              : logic.groupSetupLogic.imLogic.userInfo.value.nickname,
          onSave: logic.save,
          saving: logic.saving.value,
          onAvatarTap: isGroupName && !logic.saving.value
              ? () => _showAvatarActions(context)
              : null,
        ));
  }
}
