import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/app_controller.dart';
import '../../../core/controller/im_controller.dart';
import '../../../routes/app_navigator.dart';
import '../chat_logic.dart';
import '../../conversation/conversation_logic.dart';
import 'chat_history_search_page.dart';

class ChatSetupLogic extends GetxController {
  final chatLogic = Get.find<ChatLogic>(tag: GetTags.chat);
  final appLogic = Get.find<AppController>();
  final imLogic = Get.find<IMController>();
  late Rx<ConversationInfo> conversationInfo;
  late StreamSubscription ccSub;
  late StreamSubscription fcSub;

  String get conversationID => conversationInfo.value.conversationID;

  bool get isPinned => conversationInfo.value.isPinned == true;
  final updating = false.obs;
  bool get isMuted => conversationInfo.value.recvMsgOpt == 2;

  Future<void> setPinned(bool value) async {
    if (updating.value) return;
    updating.value = true;
    try {
      await Get.find<ConversationLogic>()
          .setPinned(conversationInfo.value, value);
      conversationInfo.refresh();
    } finally {
      updating.value = false;
    }
  }

  Future<void> setMuted(bool value) async {
    if (updating.value) return;
    updating.value = true;
    try {
      await Get.find<ConversationLogic>()
          .setNotDisturb(conversationInfo.value, value);
      conversationInfo.refresh();
    } finally {
      updating.value = false;
    }
  }

  void searchHistory() =>
      Get.to(() => ChatHistorySearchPage(conversationID: conversationID));

  Future<void> setBackground() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || isClosed) return;
      final path =
          '${Config.cachePath}/chat_background_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(image.path).copy(path);
      await DataSp.putChatBackground(chatLogic.otherId, path);
      chatLogic.background.value = path;
    } catch (_) {
      IMViews.showToast(StrRes.saveFailed);
    }
  }

  Future<void> clearHistory() async {
    final confirmed = await Get.dialog<bool>(CustomDialog(
        title: 'clearThisChatConfirm'.tr, rightText: StrRes.delete));
    if (confirmed != true) return;
    try {
      await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.conversationManager
              .clearConversationAndDeleteAllMsg(
                  conversationID: conversationID));
      chatLogic.clearAllMessage();
    } catch (_) {
      IMViews.showToast(StrRes.saveFailed);
    }
  }

  @override
  void onClose() {
    ccSub.cancel();
    fcSub.cancel();
    super.onClose();
  }

  @override
  void onInit() {
    conversationInfo = Rx(Get.arguments['conversationInfo']);
    final sourceID =
        conversationInfo.value.conversationType == ConversationType.single
            ? conversationInfo.value.userID
            : conversationInfo.value.groupID;
    OpenIM.iMManager.conversationManager
        .getOneConversation(
            sourceID: sourceID!,
            sessionType: conversationInfo.value.conversationType!)
        .then((value) {
      conversationInfo.value = value;
    });

    ccSub = imLogic.conversationChangedSubject.listen((newList) {
      for (var newValue in newList) {
        if (newValue.conversationID == conversationID) {
          conversationInfo.update((val) {
            val?.burnDuration = newValue.burnDuration ?? 30;
            val?.isPrivateChat = newValue.isPrivateChat;
            val?.isPinned = newValue.isPinned;

            val?.recvMsgOpt = newValue.recvMsgOpt;
            val?.isMsgDestruct = newValue.isMsgDestruct;
            val?.msgDestructTime = newValue.msgDestructTime;
            val?.showName = newValue.showName;
          });
          break;
        }
      }
    });

    fcSub = imLogic.friendInfoChangedSubject.listen((value) {
      if (conversationInfo.value.userID == value.userID) {
        conversationInfo.update((val) {
          val?.showName = value.getShowName();
          val?.faceURL = value.faceURL;
        });
      }
    });
    super.onInit();
  }

  void createGroup() => AppNavigator.startCreateGroup(defaultCheckedList: [
        UserInfo(
          userID: conversationInfo.value.userID,
          faceURL: conversationInfo.value.faceURL,
          nickname: conversationInfo.value.showName,
        ),
        OpenIM.iMManager.userInfo,
      ]);

  void viewUserInfo() => AppNavigator.startUserProfilePane(
        userID: conversationInfo.value.userID!,
        nickname: conversationInfo.value.showName,
        faceURL: conversationInfo.value.faceURL,
      );
}
