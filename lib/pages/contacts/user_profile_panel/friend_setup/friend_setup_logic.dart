import 'package:openim/core/user_activity/activity_sdk.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../routes/app_navigator.dart';
import '../../../../services/chat_history_cache.dart';
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

  void addBlacklist() async {
    var confirm =
        await Get.dialog(CustomDialog(title: StrRes.areYouSureAddBlacklist));
    if (confirm == true) {
      await OpenIM.iMManager.friendshipManager.addBlacklist(
        userID: userProfilesLogic.userInfo.value.userID!,
      );
      userProfilesLogic.userInfo.update((val) {
        val?.isBlacklist = true;
      });
    }
  }

  void removeBlacklist() async {
    await OpenIM.iMManager.friendshipManager.removeBlacklist(
      userID: userProfilesLogic.userInfo.value.userID!,
    );
    userProfilesLogic.userInfo.update((val) {
      val?.isBlacklist = false;
    });
  }

  void deleteFromFriendList() async {
    var confirm = await Get.dialog(CustomDialog(
      title: StrRes.areYouSureDelFriend,
      rightText: StrRes.delete,
    ));
    if (confirm) {
      await LoadingView.singleton.wrap(asyncFunction: () async {
        await observeUserActivity(
            'friend_delete',
            () => OpenIM.iMManager.friendshipManager.deleteFriend(
                  userID: userProfilesLogic.userInfo.value.userID!,
                ));
        userProfilesLogic.userInfo.update((val) {
          val?.isFriendship = false;
        });

        final userIDList = [
          userProfilesLogic.userInfo.value.userID,
          OpenIM.iMManager.userID,
        ];
        userIDList.sort();
        final conversationID = 'si_${userIDList.join('_')}';
        final accountID = OpenIM.iMManager.userID;

        await OpenIM.iMManager.conversationManager
            .deleteConversationAndDeleteAllMsg(conversationID: conversationID);

        if (Get.isRegistered<ChatLogic>(tag: GetTags.chat)) {
          final chat = Get.find<ChatLogic>(tag: GetTags.chat);
          if (!chat.isClosed &&
              chat.conversationInfo.conversationID == conversationID) {
            chat.clearAllMessage();
          }
        }
        ChatHistoryCache.removeConversation(accountID, conversationID);

        conversationLogic.list
            .removeWhere((e) => e.conversationID == conversationID);
      });

      if (userProfilesLogic.offAllWhenDelFriend == true) {
        AppNavigator.startBackMain();
      } else {
        Get.back();
      }
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
          await ChatMessageSender().sendRaw(card, target);
        } on MessageSendSessionChanged {
          return;
        }
      }
    }
  }

  void setFriendRemark() => AppNavigator.startSetFriendRemark();
}
