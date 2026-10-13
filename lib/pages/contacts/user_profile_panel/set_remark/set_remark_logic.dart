import 'package:flutter/cupertino.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../user_profile _panel_logic.dart';
import '../../contacts_logic.dart';

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
    final remark = graphemeTrim(inputCtrl.text);
    // Focusing the fallback nickname alone does not create a remark.
    if (remark == _originalRemark ||
        (_originalRemark.isEmpty && remark == graphemeTrim(avatarName ?? ''))) {
      Get.back();
      return;
    }
    try {
      final userID = userProfilesLogic.userInfo.value.userID!;
      final account = OpenIM.iMManager.userID;
      final sessionToken = DataSp.chatToken;
      await LoadingView.singleton.wrap(
        asyncFunction: () => OpenIM.iMManager.friendshipManager.updateFriends(
          UpdateFriendsReq(
            friendUserIDs: [userID],
            remark: remark,
          ),
        ),
      );
      if (account != OpenIM.iMManager.userID ||
          sessionToken != DataSp.chatToken) {
        return;
      }
      if (Get.isRegistered<ContactsLogic>()) {
        Get.find<ContactsLogic>().applySavedRemark(userID, remark);
      }
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
    _originalRemark = graphemeTrim(inputCtrl.text);
    super.onInit();
  }

  @override
  void onClose() {
    inputCtrl.dispose();
    super.onClose();
  }
}
