import 'package:flutter/cupertino.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../user_profile _panel_logic.dart';

class SetFriendRemarkLogic extends GetxController {
  static const maxRemarkLength = 30;

  final userProfilesLogic =
      Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile);
  late TextEditingController inputCtrl;
  late String _originalRemark;

  String? get avatarURL => userProfilesLogic.userInfo.value.faceURL;
  String? get avatarName => userProfilesLogic.userInfo.value.nickname;

  void save() async {
    if (isClosed) return;
    final remark = inputCtrl.text.trim();
    // Showing a nickname as a hint must not create a friend remark.
    if (remark == _originalRemark) {
      Get.back();
      return;
    }
    try {
      await LoadingView.singleton.wrap(
        asyncFunction: () => OpenIM.iMManager.friendshipManager.updateFriends(
          UpdateFriendsReq(
            friendUserIDs: [userProfilesLogic.userInfo.value.userID!],
            remark: remark,
          ),
        ),
      );
      if (isClosed) return;
      IMViews.showToast(StrRes.saveSuccessfully);
      Get.back(result: remark);
    } catch (_) {
      if (!isClosed) IMViews.showToast(StrRes.saveFailed);
    }
  }

  @override
  void onInit() {
    final user = userProfilesLogic.userInfo.value;
    inputCtrl = TextEditingController(text: user.remark);
    _originalRemark = inputCtrl.text.trim();
    super.onInit();
  }

  @override
  void onClose() {
    inputCtrl.dispose();
    super.onClose();
  }
}
