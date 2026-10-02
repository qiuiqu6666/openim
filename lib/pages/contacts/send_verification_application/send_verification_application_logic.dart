import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../group_profile_panel/group_profile_panel_logic.dart';

class SendVerificationApplicationLogic extends GetxController {
  final inputCtrl = TextEditingController();
  String? userID;
  String? groupID;
  String? friendGroupID;
  FriendAddSource addSource = FriendAddSource.chat;
  Map<String, String> friendAddFields = const {};
  bool _sending = false;
  JoinGroupMethod? joinGroupMethod;

  bool get isEnterGroup => groupID != null;

  bool get isAddFriend => userID != null;

  @override
  void onInit() {
    userID = Get.arguments['userID'];
    groupID = Get.arguments['groupID'];
    friendGroupID = Get.arguments['friendGroupID'];
    friendAddFields =
        Map<String, String>.from(Get.arguments['friendAddFields'] ?? {});
    addSource = resolveFriendAddSource(Get.arguments['addSource'],
        groupID: friendGroupID);
    joinGroupMethod = Get.arguments['joinGroupMethod'];
    super.onInit();
  }

  void send() async {
    if (isAddFriend) {
      _applyAddFriend();
    } else if (isEnterGroup) {
      _applyEnterGroup();
    }
  }

  _applyAddFriend() async {
    if (_sending) return;
    _sending = true;
    try {
      await LoadingView.singleton.wrap(
        asyncFunction: () => FriendAddRequest.send(
          userID: userID!,
          reason: inputCtrl.text.trim(),
          source: addSource,
          groupID: friendGroupID,
          fields: friendAddFields,
        ),
      );
      if (isClosed) return;
      Get.back();
      IMViews.showToast(StrRes.sendSuccessfully);
    } catch (error) {
      final message = friendAddErrorMessage(error,
          chinese: Get.locale?.languageCode == 'zh');
      if (message != null) {
        IMViews.showToast(message);
        return;
      }
      if (error is PlatformException) {
        if (error.code == '${SDKErrorCode.refuseToAddFriends}') {
          IMViews.showToast(StrRes.canNotAddFriends);
          return;
        }
      }
      IMViews.showToast(StrRes.sendFailed);
    } finally {
      _sending = false;
    }
  }

  _applyEnterGroup() {
    LoadingView.singleton
        .wrap(
          asyncFunction: () => OpenIM.iMManager.groupManager.joinGroup(
            groupID: groupID!,
            reason: inputCtrl.text.trim(),
            joinSource: joinGroupMethod == JoinGroupMethod.qrcode ? 4 : 3,
          ),
        )
        .then((value) => IMViews.showToast(StrRes.sendSuccessfully))
        .then((value) => Get.back())
        .catchError((e) => IMViews.showToast(StrRes.sendFailed));
  }
}
