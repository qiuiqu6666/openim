import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../../services/chat_history_cache.dart';
import '../../../services/chat_revocation_notice.dart';

/// Pending mentions are conversation state, not properties of the latest message.
String? conversationMentionTag(ConversationInfo info) {
  if (!info.isGroupChat) return null;
  final everyone = '[@${StrRes.everyone}]';
  final me = '[${StrRes.someoneMentionMe}]';
  return switch (info.groupAtType) {
    GroupAtType.atMe => me,
    GroupAtType.atAll => everyone,
    GroupAtType.atAllAtMe => '$everyone$me',
    _ => null,
  };
}

/// Draft and announcement labels; pending mention labels render independently.
String? conversationPrefixTag(ConversationInfo info) {
  if (info.draftText?.isNotEmpty == true) return '[${StrRes.draftText}]';
  if (info.groupAtType == GroupAtType.groupNotification) {
    return '[${StrRes.groupAc}]';
  }
  return null;
}

/// Shared last-message formatting. Draft bodies and unread badges stay with callers.
String conversationLatestMessageText(ConversationInfo info) {
  try {
    final latest = info.latestMsg;
    if (latest == null) return '';
    final message = ChatHistoryCache.applyRevocation(
        OpenIM.iMManager.userID, latest);
    if (message.contentType == MessageType.revokeMessageNotification) {
      return ChatRevocationNotice.text(message, OpenIM.iMManager.userID);
    }
    final notification = IMUtils.parseNtf(message, isConversation: true);
    if (notification != null) return notification;
    final text = IMUtils.parseMsg(message, isConversation: true);
    if (info.isSingleChat || message.sendID == OpenIM.iMManager.userID) {
      return text;
    }
    final senderName = graphemeTrim(message.senderNickname ?? '');
    // Some server-created messages omit the sender nickname.
    if (senderName.isEmpty) return text;
    return '$senderName: $text ';
  } catch (error, stack) {
    Logger.print('------e:$error s:$stack');
    return '[${StrRes.unsupportedMessage}]';
  }
}
