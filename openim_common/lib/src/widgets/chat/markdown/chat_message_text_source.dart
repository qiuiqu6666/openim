import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'chat_draw_report_text.dart';
import 'chat_agent_report_text.dart';

/// Ordinary text, mentions and replies stay literal, as in 99chat. Only the
/// explicit rich-text SDK type may use Markdown when it has no format entities.
bool chatMessageAllowsMarkdown(Message message) {
  if (message.contentType != MessageType.advancedText) return false;

  // Generated report separators remain literal even in a rich-text envelope.
  final text = chatMessageTextSource(message);
  if (isChatDrawReportText(text) || isChatAgentReportText(text)) return false;
  final ex = message.ex;
  if (ex == null || ex.isEmpty) return true;
  try {
    final metadata = jsonDecode(ex);
    return metadata is! Map || metadata['sangongReport'] is! Map;
  } on FormatException {
    return true;
  }
}

/// Bubble text keeps line breaks; conversation summaries still use parseMsg.
/// Mention names are a display adaptation and never mutate the SDK message.
String chatMessageTextSource(Message message) {
  if (message.hasExpired) return IMUtils.parseMsg(message);
  switch (message.contentType) {
    case MessageType.text:
      return message.textElem?.content ?? '';
    case MessageType.quote:
      return message.quoteElem?.text ?? '';
    case MessageType.advancedText:
      return message.advancedTextElem?.text ?? '';
    case MessageType.atText:
      var text = message.atTextElem?.text ?? '';
      final members = [...?message.atTextElem?.atUsersInfo]..sort((a, b) =>
          (b.atUserID?.length ?? 0).compareTo(a.atUserID?.length ?? 0));
      for (final member in members) {
        final id = member.atUserID;
        final name = member.groupNickname;
        if (id != null && id.isNotEmpty && name != null) {
          text = text.replaceAll('@$id', '@${IMUtils.getAtNickname(id, name)}');
        }
      }
      return text.replaceAll('@atAllTag', '@${StrRes.everyone}');
    default:
      return IMUtils.parseMsg(message);
  }
}
