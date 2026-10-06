import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

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
    final message = info.latestMsg;
    if (message == null) return '';
    final notification = IMUtils.parseNtf(message, isConversation: true);
    if (notification != null) return notification;
    final text = IMUtils.parseMsg(message, isConversation: true);
    if (info.isSingleChat || message.sendID == OpenIM.iMManager.userID) {
      return text;
    }
    return '${message.senderNickname}: $text ';
  } catch (error, stack) {
    Logger.print('------e:$error s:$stack');
    return '[${StrRes.unsupportedMessage}]';
  }
}
