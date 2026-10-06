import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/app_controller.dart';
import '../../../core/controller/im_controller.dart';
import '../../../routes/app_navigator.dart';
import '../chat_logic.dart';
import '../../conversation/conversation_logic.dart';
import '../../customer_service/customer_service.dart';
import '../../mine/settings/pages/chat_background_page.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'chat_history_search_page.dart';

class ChatSetupLogic extends GetxController {
  final chatLogic = Get.find<ChatLogic>(tag: GetTags.chat);
  final appLogic = Get.find<AppController>();
  final imLogic = Get.find<IMController>();
  late Rx<ConversationInfo> conversationInfo;
  late StreamSubscription ccSub;
  late StreamSubscription fcSub;
  late String _ownerID;
  String? _imToken;
  String? _chatToken;
  bool _closing = false;
  bool _reporting = false;
  int _revision = 0;
  int _settingsRevision = 0;

  bool get _active =>
      !_closing &&
      !isClosed &&
      _ownerID == OpenIM.iMManager.userID &&
      _imToken == DataSp.imToken &&
      _chatToken == DataSp.chatToken;

  String get conversationID => conversationInfo.value.conversationID;

  bool get isPinned => conversationInfo.value.isPinned == true;
  final updating = false.obs;
  final clearing = false.obs;
  bool get isMuted => conversationInfo.value.recvMsgOpt == 2;

  Future<void> setPinned(bool value) async {
    if (!_active || updating.value || clearing.value) return;
    ++_revision;
    final revision = ++_settingsRevision;
    final snapshot = ConversationInfo.fromJson(conversationInfo.value.toJson());
    updating.value = true;
    try {
      await Get.find<ConversationLogic>().setPinned(snapshot, value);
      if (_active && revision == _settingsRevision) {
        conversationInfo.update((info) => info?.isPinned = snapshot.isPinned);
      }
    } catch (_) {
      if (_active) IMViews.showToast(StrRes.saveFailed);
    } finally {
      if (_active) updating.value = false;
    }
  }

  Future<void> setMuted(bool value) async {
    if (!_active || updating.value || clearing.value) return;
    ++_revision;
    final revision = ++_settingsRevision;
    final snapshot = ConversationInfo.fromJson(conversationInfo.value.toJson());
    updating.value = true;
    try {
      await Get.find<ConversationLogic>().setNotDisturb(snapshot, value);
      if (_active && revision == _settingsRevision) {
        conversationInfo
            .update((info) => info?.recvMsgOpt = snapshot.recvMsgOpt);
      }
    } catch (_) {
      if (_active) IMViews.showToast(StrRes.saveFailed);
    } finally {
      if (_active) updating.value = false;
    }
  }

  void searchHistory() =>
      Get.to(() => ChatHistorySearchPage(conversationID: conversationID));

  Future<void> setBackground() async {
    if (!_active) return;
    await Get.to(
      () => ChatBackgroundPage(
        conversationId: chatLogic.otherId,
        conversationName:
            conversationInfo.value.showName ?? chatLogic.nickname.value,
      ),
    );
    if (_active) await chatLogic.reloadChatBackground();
  }

  Future<void> reportConversation() async {
    if (!_active || _reporting) return;
    final context = Get.context;
    if (context == null || !context.mounted) return;
    final peer = conversationInfo.value.userID?.trim() ?? '';
    if (conversationInfo.value.conversationType != ConversationType.single ||
        peer.isEmpty) {
      IMViews.showToast(settingsText(context,
          zh: '无法读取投诉对象', en: 'Unable to identify the reported user.'));
      return;
    }
    if (peer == _ownerID) {
      IMViews.showToast(settingsText(context,
          zh: '不能投诉自己', en: 'You cannot report yourself.'));
      return;
    }
    _reporting = true;
    try {
      final confirmed = await showSettingsConfirm(context,
          title: settingsText(context, zh: '投诉', en: 'Report'),
          message: settingsText(context,
              zh: '如需投诉此聊天，请联系人工客服，并提供对方账号：$peer。',
              en:
                  'To report this chat, contact customer service and provide the other user’s account: $peer.'),
          confirmText: settingsText(context,
              zh: '联系人工客服', en: 'Contact customer service'));
      if (!confirmed || !_active || !context.mounted) return;
      await showCustomerServiceSheet(context);
    } catch (_) {
      if (_active && context.mounted) {
        IMViews.showToast(settingsText(context,
            zh: '无法打开在线客服，请稍后重试',
            en: 'Unable to open customer service. Please try again.'));
      }
    } finally {
      _reporting = false;
    }
  }

  Future<void> clearHistory() async {
    if (!_active || clearing.value) return;
    final id = conversationID;
    clearing.value = true;
    try {
      final context = Get.context;
      final bool? confirmed;
      if (context != null && context.mounted) {
        confirmed = await showSettingsConfirm(context,
            title: StrRes.clearChatHistory,
            message: 'clearThisChatConfirm'.tr,
            confirmText: StrRes.delete,
            destructive: true);
      } else {
        confirmed = await Get.dialog<bool>(CustomDialog(
            title: 'clearThisChatConfirm'.tr, rightText: StrRes.delete));
      }
      if (confirmed != true || !_active) return;
      await LoadingView.singleton.wrap(asyncFunction: () async {
        if (!_active) return;
        await OpenIM.iMManager.conversationManager
            .clearConversationAndDeleteAllMsg(conversationID: id);
      });
      if (_active) chatLogic.clearAllMessage();
    } catch (_) {
      if (_active) IMViews.showToast(StrRes.saveFailed);
    } finally {
      if (_active) clearing.value = false;
    }
  }

  @override
  void onClose() {
    _closing = true;
    ++_revision;
    ++_settingsRevision;
    ccSub.cancel();
    fcSub.cancel();
    super.onClose();
  }

  @override
  void onInit() {
    _ownerID = OpenIM.iMManager.userID;
    _imToken = DataSp.imToken;
    _chatToken = DataSp.chatToken;
    conversationInfo = Rx(Get.arguments['conversationInfo']);
    ccSub = imLogic.conversationChangedSubject.listen((newList) {
      if (!_active) return;
      for (var newValue in newList) {
        if (newValue.conversationID == conversationID) {
          ++_revision;
          ++_settingsRevision;
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
      if (!_active) return;
      if (conversationInfo.value.userID == value.userID) {
        ++_revision;
        conversationInfo.update((val) {
          val?.showName = value.getShowName();
          val?.faceURL = value.faceURL;
        });
      }
    });
    unawaited(_loadInitialConversation(_revision));
    super.onInit();
  }

  Future<void> _loadInitialConversation(int revision) async {
    final snapshot = conversationInfo.value;
    final sourceID = snapshot.conversationType == ConversationType.single
        ? snapshot.userID
        : snapshot.groupID;
    try {
      if (!_active || sourceID == null || snapshot.conversationType == null) {
        return;
      }
      final value = await OpenIM.iMManager.conversationManager
          .getOneConversation(
              sourceID: sourceID, sessionType: snapshot.conversationType!);
      if (!_active || revision != _revision) return;
      if (value.conversationID != snapshot.conversationID) {
        throw StateError('Unexpected conversation');
      }
      ++_revision;
      conversationInfo.value = value;
    } catch (_) {
      if (_active && revision == _revision) {
        IMViews.showToast(StrRes.saveFailed);
      }
    }
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
