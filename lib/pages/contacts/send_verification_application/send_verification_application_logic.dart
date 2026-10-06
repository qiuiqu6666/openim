import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../group_profile_panel/group_profile_panel_logic.dart';

class SendVerificationApplicationLogic extends GetxController {
  static const maxMessageLength = 20;
  final inputCtrl = TextEditingController();
  final sending = false.obs;
  String targetName = '', targetAccount = '';
  String? targetAvatarURL;
  String? userID;
  String? groupID;
  String? friendGroupID;
  FriendAddSource addSource = FriendAddSource.chat;
  Map<String, String> friendAddFields = const {};
  JoinGroupMethod? joinGroupMethod;

  bool get isEnterGroup => groupID != null;

  bool get isAddFriend => userID != null;

  bool get canSubmit => isAddFriend
      ? FriendAddRequest.canSend(
          userID: userID!,
          source: addSource,
          groupID: friendGroupID,
          fields: friendAddFields,
        )
      : isEnterGroup;

  String? get unavailableMessage => canSubmit
      ? null
      : Get.locale?.languageCode == 'en'
          ? 'Add this person using their chat ID, QR code, or contact card.'
          : '请通过对方的聊天号、二维码或好友名片添加。';

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
    targetName = Get.arguments['targetName'] ?? '';
    targetAvatarURL = Get.arguments['targetAvatarURL'];
    targetAccount = Get.arguments['targetAccount'] ?? '';
    final selfName = (Get.arguments['selfNickname'] as String?)?.trim() ?? '';
    if (isAddFriend && selfName.isNotEmpty) {
      final greeting = Get.locale?.languageCode == 'en'
          ? 'Hi, I’m $selfName'
          : '我是：$selfName';
      inputCtrl.text = greeting.characters.take(maxMessageLength).join();
    }
    super.onInit();
  }

  Future<void> send() async {
    if (isClosed || sending.value || !canSubmit) return;
    sending.value = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      if (isAddFriend) {
        await _applyAddFriend();
      } else {
        await _applyEnterGroup();
      }
    } finally {
      if (!isClosed) sending.value = false;
    }
  }

  Future<void> _applyAddFriend() async {
    final reason = inputCtrl.text.trim();
    try {
      await LoadingView.singleton.wrap(
        asyncFunction: () => FriendAddRequest.send(
          userID: userID!,
          reason: reason,
          source: addSource,
          groupID: friendGroupID,
          fields: friendAddFields,
        ),
      );
      if (isClosed) return;
      Get.back();
      IMViews.showToast(StrRes.sendSuccessfully);
    } catch (error) {
      if (isClosed) return;
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
    }
  }

  Future<void> _applyEnterGroup() async {
    final reason = inputCtrl.text.trim();
    try {
      await LoadingView.singleton.wrap(
        asyncFunction: () => OpenIM.iMManager.groupManager.joinGroup(
          groupID: groupID!,
          reason: reason,
          joinSource: joinGroupMethod == JoinGroupMethod.qrcode ? 4 : 3,
        ),
      );
      if (isClosed) return;
      IMViews.showToast(StrRes.sendSuccessfully);
      Get.back();
    } catch (_) {
      if (!isClosed) IMViews.showToast(StrRes.sendFailed);
    }
  }

  @override
  void onClose() {
    inputCtrl.dispose();
    super.onClose();
  }
}
