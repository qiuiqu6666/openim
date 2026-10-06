import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart' show IMUtils, StrRes;

import '../../pages/official_account/models/official_account.dart';
import 'message_notification_preferences.dart';
import 'message_notification_sound.dart';

/// Plain display data only: no platform plugin, route, SDK call or UI state.
class MessageNotificationPresentation {
  const MessageNotificationPresentation({
    required this.title,
    required this.body,
    required this.avatarURL,
    required this.isGroup,
    required this.senderName,
    required this.showReply,
    required this.enableSound,
    required this.enableVibration,
    this.soundID = MessageNotificationSoundIds.defaultId,
  });

  final String title;
  final String body;
  final String? avatarURL;
  final bool isGroup;
  final String senderName;
  final bool showReply;
  final bool enableSound;
  final bool enableVibration;
  final String soundID;
}

abstract final class MessageNotificationPolicy {
  /// Eligibility is independent of the visual banner and foreground alerts.
  static bool accepts({
    required Message message,
    required ConversationInfo conversation,
    required String currentUserID,
    int? globalRecvMsgOpt,
  }) {
    final contentType = message.contentType;
    final flags = _attachedFlags(message);
    return currentUserID.trim().isNotEmpty &&
        conversation.conversationID.isNotEmpty &&
        message.sendID != currentUserID &&
        contentType != null &&
        contentType != MessageType.typing &&
        contentType < MessageType.notificationBegin &&
        conversation.conversationType != ConversationType.notification &&
        message.sessionType != ConversationType.notification &&
        message.attachedInfoElem?.notSenderNotificationPush != true &&
        flags['notSenderNotificationPush'] != true &&
        globalRecvMsgOpt != 2 &&
        (conversation.recvMsgOpt ?? 0) == 0;
  }

  static MessageNotificationPresentation? present({
    required Message message,
    required ConversationInfo conversation,
    required String currentUserID,
    required bool isForeground,
    String? activeConversationID,
    required MessageNotificationPreferences preferences,
    int? globalRecvMsgOpt,
  }) {
    final flags = _attachedFlags(message);
    if (!accepts(
        message: message,
        conversation: conversation,
        currentUserID: currentUserID,
        globalRecvMsgOpt: globalRecvMsgOpt)) {
      return null;
    }
    if (isForeground) {
      if (!preferences.notifyWhenOpen ||
          activeConversationID == conversation.conversationID) {
        return null;
      }
    } else if (!preferences.notifyWhenClosed) {
      return null;
    }

    final preview =
        isForeground ? preferences.openedPreview : preferences.closedPreview;
    final isOfficialNotification =
        conversation.conversationType == ConversationType.single &&
            OfficialAccount.from(
                    userID: conversation.userID ?? message.sendID,
                    ex: conversation.ex) !=
                null;
    final showReply = preferences.quickReply && !isOfficialNotification;
    final generic = StrRes.offlineMessage;
    if (preview == MessageNotificationPreview.none) {
      // Do not retain source names or a group-avatar hint in anonymous data.
      return MessageNotificationPresentation(
        title: generic,
        body: generic,
        avatarURL: null,
        isGroup: false,
        senderName: '',
        showReply: showReply,
        enableSound: !isForeground || preferences.messageSoundEnabled,
        enableVibration: !isForeground || preferences.vibration,
        soundID: preferences.messageSound,
      );
    }

    final isGroup =
        conversation.conversationType == ConversationType.superGroup ||
            conversation.conversationType == 2 ||
            message.sessionType == ConversationType.superGroup ||
            message.sessionType == 2 ||
            _nonEmpty(conversation.groupID) != null ||
            _nonEmpty(message.groupID) != null;
    final senderName = _oneLine(message.senderNickname ?? '');
    final conversationName = _oneLine(conversation.showName ?? '');
    final title = conversationName.isNotEmpty
        ? conversationName
        : isGroup
            ? StrRes.groupChat
            : senderName.isNotEmpty
                ? senderName
                : generic;
    final avatar = _nonEmpty(conversation.faceURL) ??
        (isGroup ? null : _nonEmpty(message.senderFaceUrl));
    final isPrivate = conversation.isPrivateChat == true ||
        message.attachedInfoElem?.isPrivateChat == true ||
        flags['isPrivateChat'] == true;
    var body = generic;
    if (preview == MessageNotificationPreview.detail && !isPrivate) {
      // Only SDK message elements supply content. Never use offlinePush body,
      // custom HTML or a speculative decryption of an extension field.
      final detail = _oneLine(IMUtils.parseMsg(message));
      if (detail.isNotEmpty) body = detail;
    }
    if (preview == MessageNotificationPreview.detail &&
        isGroup &&
        senderName.isNotEmpty) {
      body = '$senderName: $body';
    }
    return MessageNotificationPresentation(
      title: title,
      body: body,
      avatarURL: avatar,
      isGroup: isGroup,
      senderName: senderName,
      showReply: showReply,
      enableSound: !isForeground || preferences.messageSoundEnabled,
      enableVibration: !isForeground || preferences.vibration,
      soundID: preferences.messageSound,
    );
  }

  static Map<Object?, Object?> _attachedFlags(Message message) {
    final raw = message.attachedInfo;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _oneLine(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
}
