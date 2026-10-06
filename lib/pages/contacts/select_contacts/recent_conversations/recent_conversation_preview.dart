import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import '../../../../services/chat_history_cache.dart';
import '../../../conversation/peek/conversation_peek_loader.dart';
import '../../../conversation/drafts/conversation_draft_text.dart';
import '../../../conversation/summary/conversation_latest_message_text.dart';

/// Display segments retain the real draft state, independent of message text.
class RecentConversationPreviewData {
  const RecentConversationPreviewData({
    this.unread = '',
    this.mention = '',
    this.prefix = '',
    this.content = '',
    this.isDraft = false,
  });

  final String unread;
  final String mention;
  final String prefix;
  final String content;
  final bool isDraft;

  String get text => '$unread$mention$prefix$content';
}

/// A recipient preview never opens history or exposes retained private content.
String recentConversationPreview(ConversationInfo? info) =>
    recentConversationPreviewData(info).text;

RecentConversationPreviewData recentConversationPreviewData(
    ConversationInfo? info) {
  if (info == null) return const RecentConversationPreviewData();
  final unread = info.unreadCount > 0
      ? '[${sprintf(StrRes.nPieces, [info.unreadCount])}] '
      : '';
  final tag = conversationPrefixTag(info) ?? '';
  return RecentConversationPreviewData(
    unread: unread,
    mention: conversationMentionTag(info) ?? '',
    prefix: tag,
    content: _content(info).replaceAll(RegExp(r'[\r\n]+'), ' '),
    isDraft: info.draftText?.isNotEmpty == true,
  );
}

String _content(ConversationInfo info) {
  final draft = conversationDraftText(info.draftText);
  final message = info.latestMsg;
  if (draft == null && message == null) return '';
  if (info.isPrivateChat == true) return '[${StrRes.burnAfterReading}]';
  if (draft != null) return draft;
  if (message == null) return '';
  if (ChatHistoryCache.isRemoved(
      OpenIM.iMManager.userID, message.clientMsgID)) {
    return '';
  }
  if (message.hasExpired) return 'sdkExpired'.tr;
  if (message.contentType == MessageType.revokeMessageNotification) {
    return '[${StrRes.revokeMsg}]';
  }
  if (ConversationPeekLoader.containsPrivateContent(message)) {
    return '[${StrRes.burnAfterReading}]';
  }
  return conversationLatestMessageText(info);
}
