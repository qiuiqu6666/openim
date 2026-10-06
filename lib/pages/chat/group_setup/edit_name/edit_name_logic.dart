import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim_common/openim_common.dart';

enum EditNameType {
  myGroupMemberNickname,
  groupNickname,
}

class EditGroupNameLogic extends GetxController {
  final groupSetupLogic = Get.find<GroupSetupLogic>();
  late TextEditingController inputCtrl;
  late EditNameType type;
  String? faceUrl;
  late String _originalName;
  final saving = false.obs;

  @override
  void onInit() {
    type = Get.arguments['type'];
    faceUrl = Get.arguments['faceUrl'];
    inputCtrl = TextEditingController(
      text: type == EditNameType.groupNickname
          ? groupSetupLogic.groupInfo.value.groupName
          : groupSetupLogic.myGroupNickname,
    );
    _originalName = inputCtrl.text.trim();
    super.onInit();
  }

  @override
  void onClose() {
    inputCtrl.dispose();
    super.onClose();
  }

  String? get title => type == EditNameType.myGroupMemberNickname
      ? StrRes.myGroupMemberNickname
      : StrRes.groupName;

  Future<void> save() async {
    if (isClosed || saving.value) return;
    final name = inputCtrl.text.trim();
    if (name.characters.length > 30) {
      return IMViews.showToast(StrRes.createGroupTips);
    }
    // Avatar changes are saved separately by GroupSetupLogic. Sending the
    // original name again creates an unnecessary group-name notification.
    saving.value = true;
    if (name == _originalName) {
      Get.back();
      return;
    }
    var completed = false;
    try {
      await LoadingView.singleton.wrap(asyncFunction: () async {
        if (isClosed) return;
        if (type == EditNameType.groupNickname) {
          await OpenIM.iMManager.groupManager.setGroupInfo(GroupInfo(
              groupID: groupSetupLogic.groupInfo.value.groupID,
              groupName: name));
        } else if (type == EditNameType.myGroupMemberNickname) {
          await OpenIM.iMManager.groupManager.setGroupMemberInfo(
              groupMembersInfo: SetGroupMemberInfo(
            groupID: groupSetupLogic.groupInfo.value.groupID,
            userID: OpenIM.iMManager.userID,
            nickname: name,
          ));
        }
      });
      if (isClosed) return;
      _originalName = name;
      completed = true;
      IMViews.showToast(StrRes.setSuccessfully);
      Get.back();
    } catch (_) {
      if (!isClosed) IMViews.showToast(StrRes.saveFailed);
    } finally {
      // Keep the editor locked during the route's closing animation, too.
      if (!isClosed && !completed) saving.value = false;
    }
  }
}
