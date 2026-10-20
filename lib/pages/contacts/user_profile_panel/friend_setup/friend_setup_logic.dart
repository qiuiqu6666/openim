import 'package:openim_common/localization.dart';
import 'package:openim/core/user_activity/activity_sdk.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../routes/app_navigator.dart';
import '../../../../services/chat_message_sender.dart';
import '../../../../services/favorite_send_coordinator.dart';
import '../../../../services/messaging/message_send_session.dart';
import '../../../chat/chat_logic.dart';
import '../../../conversation/conversation_logic.dart';
import '../../select_contacts/select_contacts_logic.dart';
import '../user_profile _panel_logic.dart';

class FriendSetupLogic extends GetxController {
  final conversationLogic = Get.find<ConversationLogic>();
  final userProfilesLogic =
      Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile);
  late String userID;
  final _accountID = OpenIM.iMManager.userID;
  final _token = DataSp.chatToken;
  bool _deleting = false;
  bool _friendDeleted = false;
  bool get _active =>
      !isClosed &&
      !userProfilesLogic.isClosed &&
      _accountID == OpenIM.iMManager.userID &&
      _token == DataSp.chatToken &&
      conversationLogic.isSessionActive;

  @override
  void onInit() {
    userID = Get.arguments['userID'];
    super.onInit();
  }

  void toggleBlacklist() {
    if (userProfilesLogic.userInfo.value.isBlacklist == true) {
      removeBlacklist();
    } else {
      addBlacklist();
    }
  }

  Future<void> addBlacklist() => userProfilesLogic.setBlacklist(true);

  Future<void> removeBlacklist() => userProfilesLogic.setBlacklist(false);

  Future<void> deleteFromFriendList() async {
    if (!_active || _deleting) return;
    final peer = userProfilesLogic.userInfo.value.userID;
    if (peer == null || peer.isEmpty) return;
    _deleting = true;
    try {
      final confirm = await Get.dialog<bool>(CustomDialog(
        title: StrRes.areYouSureDelFriend,
        rightText: StrRes.delete,
      ));
      if (confirm != true || !_active) return;
      await LoadingView.singleton.wrap(asyncFunction: () async {
        if (!_active) return;
        if (!_friendDeleted) {
          await observeUserActivity(
              'friend_delete',
              () => OpenIM.iMManager.friendshipManager
                  .deleteFriend(userID: peer));
          if (!_active) return;
          _friendDeleted = true;
          userProfilesLogic.userInfo.update((val) => val?.isFriendship = false);
        }
        await conversationLogic.hidePeerConversation(peer);
      });
      if (!_active) return;
      if (userProfilesLogic.offAllWhenDelFriend == true) {
        AppNavigator.startBackMain();
      } else {
        Get.back();
      }
    } catch (error) {
      if (_active) {
        IMViews.showToast(_friendDeleted
            ? (Get.locale?.languageCode == 'en'
                ? 'Friend deleted. Could not remove the conversation. Please retry.'
                : AppCopy.text('好友已删除，会话移除失败，请重试。'))
            : (Get.locale?.languageCode == 'en'
                ? 'Could not delete friend. Please retry.'
                : AppCopy.text('删除好友失败，请重试。')));
      }
    } finally {
      _deleting = false;
    }
  }

  Future<void> recommendToFriend() async {
    final isRegistered = Get.isRegistered<ChatLogic>(tag: GetTags.chat);
    if (isRegistered) {
      final logic = Get.find<ChatLogic>(tag: GetTags.chat);
      logic.recommendFriendCarte(
          UserInfo.fromJson(userProfilesLogic.userInfo.value.toJson()));
      return;
    }
    final sendSession = MessageSendSession.capture();
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.recommend,
      sharedContact:
          UserInfo.fromJson(userProfilesLogic.userInfo.value.toJson()),
      ex: '[${StrRes.carte}]${userProfilesLogic.userInfo.value.nickname}',
    );
    if (!sendSession.current) return;
    if (null != result) {
      final customEx = result['customEx'];
      final checkedList = result['checkedList'];
      var sentCount = 0;
      for (var info in checkedList) {
        if (!sendSession.current) return;
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);
        final String extension;
        try {
          extension = await createFriendCardExtension(
              userProfilesLogic.userInfo.value.userID!);
        } catch (error) {
          if (isSilentFriendRisk(error)) return;
          rethrow;
        }
        if (!sendSession.current) return;
        final target = FavoriteTarget(
          conversationID: '',
          userID: userID,
          groupID: groupID,
          sessionType: APNsOfflinePushInfo.sessionTypeForSelection(info),
        );
        try {
          if (customEx is String && customEx.isNotEmpty) {
            final message = await OpenIM.iMManager.messageManager
                .createTextMessage(text: customEx);
            if (!sendSession.current) return;
            await ChatMessageSender().sendRaw(message, target);
          }
          if (!sendSession.current) return;
          final card = await OpenIM.iMManager.messageManager.createCardMessage(
            userID: userProfilesLogic.userInfo.value.userID!,
            ex: extension,
            nickname: userProfilesLogic.userInfo.value.showName,
            faceURL: userProfilesLogic.userInfo.value.faceURL,
          );
          if (!sendSession.current) return;
          final sent = await ChatMessageSender().sendRaw(card, target);
          if (!sendSession.current ||
              sent.status != MessageStatus.succeeded ||
              sent.clientMsgID != card.clientMsgID) {
            return;
          }
          sentCount++;
        } on MessageSendSessionChanged {
          return;
        }
      }
      if (sentCount > 0 && sendSession.current) {
        IMViews.showToast(StrRes.sendSuccessfully, centered: true);
      }
    }
  }

  void setFriendRemark() => AppNavigator.startSetFriendRemark();
}
