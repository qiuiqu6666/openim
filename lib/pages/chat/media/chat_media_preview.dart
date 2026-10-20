import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../../routes/app_navigator.dart';
import '../favorites/chat_favorites_controller.dart';
import '../history_search/navigation/chat_history_message_navigation.dart';
import '../messages/chat_delivery_controller.dart';
import '../messages/chat_message_actions.dart';
import '../messages/forwarding/chat_forwarding_controller.dart';
import '../messages/forwarding/pending_forward.dart';
import '../messages/selection/message_selection_delete_sheet.dart';
import '../../contacts/select_contacts/selection/contact_selection_policy.dart';
import 'chat_media_message_locator.dart';
import 'chat_media_share_recipients.dart';
import 'chat_picture_gallery.dart';

/// Chat-backed media uses the same capabilities regardless of the entry page.
/// Each action re-reads the selected SDK record rather than trusting search data.
class ChatMediaPreview {
  static Future<void> open(
    BuildContext context, {
    required String conversationID,
    required Message selected,
    required Iterable<Message> messages,
    required bool Function() isCurrent,
    void Function(String id)? onDeleted,
    ChatHistoryMessageNavigation? navigation,
    ChatPictureGallery? gallery,
  }) async {
    final owner = (
      OpenIM.iMManager.userID,
      OpenIM.iMManager.token,
      DataSp.chatToken,
      DataSp.imToken
    );
    bool current() =>
        context.mounted &&
        isCurrent() &&
        owner ==
            (
              OpenIM.iMManager.userID,
              OpenIM.iMManager.token,
              DataSp.chatToken,
              DataSp.imToken
            );
    if (!current() ||
        selected.hasExpired ||
        selected.attachedInfoElem?.isPrivateChat == true) {
      return;
    }
    final media = gallery ??
        await ChatPictureGallery.fromMessages(
            messages.where((m) =>
                !m.hasExpired && m.attachedInfoElem?.isPrivateChat != true),
            selected);
    if (!context.mounted || !current() || media.sources.isEmpty) return;
    final actions = _PreviewActions(
        context: context,
        conversationID: conversationID,
        gallery: media,
        isCurrent: current,
        onDeleted: onDeleted);
    var open = true;
    final recipients =
        ChatMediaShareRecipients(isCurrent: () => open && current());
    final locate = navigation ?? ChatHistoryMessageNavigation();
    await IMUtils.previewMediaFile(
      context: context,
      message: selected,
      sources: media.sources,
      initialIndex: media.initialIndex,
      onAutoPlay: (index) =>
          index == media.initialIndex && media.sources[index].isVideo,
      loadShareRecipients: recipients.load,
      onForwardTo: (index, recipient) =>
          actions.run(index, (message, runtime) async {
        if (runtime.actions.canForward(message)) {
          await recipients.stage(message, recipient);
        }
      }),
      onForward: (index) => actions.run(index,
          (message, runtime) => runtime.forwarding.forwardMessage(message)),
      onFavorite: (index) => actions.run(index,
          (message, runtime) => runtime.favorites.favoriteMessage(message)),
      onDelete: (index) async {
        if (!current()) return;
        final confirmed = await MessageSelectionDeleteSheet.show(context, 1,
            singleMessage: true);
        if (confirmed && current()) {
          await actions.run(index, (message, runtime) async {
            await runtime.actions.deleteMessages([message]);
          });
        }
      },
      onViewInChat: (index) {
        final message = media.messageAt(index);
        if (message != null && current()) {
          locate.open(context,
              conversationID: conversationID,
              message: message,
              isEntryCurrent: current);
        }
      },
    ).whenComplete(() => open = false);
  }
}

class _PreviewActions {
  _PreviewActions(
      {required this.context,
      required this.conversationID,
      required this.gallery,
      required this.isCurrent,
      this.onDeleted});
  final BuildContext context;
  final String conversationID;
  final ChatPictureGallery gallery;
  final bool Function() isCurrent;
  final void Function(String)? onDeleted;
  bool _busy = false;

  Future<void> run(int index,
      Future<void> Function(Message, _ActionRuntime) operation) async {
    if (_busy || !isCurrent()) return;
    final snapshot = gallery.messageAt(index);
    if (snapshot?.clientMsgID == null) return;
    _busy = true;
    _ActionRuntime? runtime;
    try {
      final message = await ChatMediaMessageLocator.findStoredMessage(
          conversationID: conversationID, clientMsgID: snapshot!.clientMsgID!);
      if (!isCurrent()) return;
      if (message == null ||
          message.hasExpired ||
          message.attachedInfoElem?.isPrivateChat == true ||
          !(message.isPictureType || message.isVideoType)) {
        IMViews.showToast('mediaMessageUnavailable'.tr);
        return;
      }
      final conversations = await OpenIM.iMManager.conversationManager
          .getMultipleConversation(conversationIDList: [conversationID]);
      if (!isCurrent()) return;
      final matching =
          conversations.where((c) => c.conversationID == conversationID);
      if (matching.length != 1 ||
          matching.single.conversationType == ConversationType.notification ||
          !ContactSelectionPolicy.allows(matching.single)) {
        IMViews.showToast('mediaMessageUnavailable'.tr);
        return;
      }
      runtime = _ActionRuntime(matching.single, message, isCurrent, (id) {
        if (!isCurrent()) return;
        if (Get.isRegistered<IMController>()) {
          Get.find<IMController>().messageDeleted(message);
        }
        onDeleted?.call(id);
      });
      await operation(message, runtime);
    } catch (_) {
      if (isCurrent()) IMViews.showToast('mediaMessageUnavailable'.tr);
    } finally {
      runtime?.close();
      _busy = false;
    }
  }
}

/// Reuse the existing message policies, confirmation/delivery and favorites.
/// No timeline controller is registered or replaced by a history preview.
class _ActionRuntime {
  _ActionRuntime(ConversationInfo conversation, Message message,
      bool Function() current, void Function(String) removed) {
    final messages = <Message>[message].obs;
    delivery = ChatDeliveryController(
        messageList: messages,
        conversation: () => conversation,
        isClosed: () => !current(),
        groupStatus: () => null,
        scrollBottom: () {},
        resetInput: (_) {});
    actions = ChatMessageActions(
        conversationID: () => conversation.conversationID,
        removeMessage: removed,
        isClosed: () => !current());
    forwarding = ChatForwardingController(
        delivery: delivery,
        messages: () => messages,
        isClosed: () => !current(),
        isGroupChat: () => conversation.isGroupChat,
        nickname: () => conversation.showName ?? '',
        faceUrl: () => conversation.faceURL ?? '',
        canForward: actions.canForward,
        closeToolbox: () {},
        stageForward: (items, recipient, merged) => AppNavigator.stageForward(
            PendingForward(items, recipient, merged: merged),
            isCurrent: current));
    _createFavorites = () => ChatFavoritesController(
        messageList: messages,
        delivery: delivery,
        conversation: () => conversation,
        accountID: OpenIM.iMManager.userID,
        isClosed: () => !current(),
        sendingMuted: () => false,
        isInvalidGroup: () => false,
        displayName: () => conversation.showName ?? '',
        unfocus: () {});
  }
  late final ChatDeliveryController delivery;
  late final ChatMessageActions actions;
  late final ChatForwardingController forwarding;
  late final ChatFavoritesController Function() _createFavorites;
  ChatFavoritesController? _favorites;
  ChatFavoritesController get favorites => _favorites ??= _createFavorites();
  void close() {
    _favorites?.dispose();
    delivery.close();
  }
}
