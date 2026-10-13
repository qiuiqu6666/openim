import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../conversation/peek/conversation_peek_loader.dart';

/// Backward-compatible SDK draft envelope. Private/expired content must never
/// be copied into a persistent draft as a quoted message snapshot.
class ChatDraft {
  const ChatDraft(this.text, this.mentions, this.quote);
  final String text;
  final Map<String, String> mentions;
  final Message? quote;

  static bool _canPersist(Message? message) =>
      message?.clientMsgID?.isNotEmpty == true &&
      !ConversationPeekLoader.containsPrivateContent(message!) &&
      !message.hasExpired &&
      message.contentType != MessageType.revokeMessageNotification;

  factory ChatDraft.decode(String draft) {
    try {
      final data = jsonDecode(draft);
      if (data is Map && data['text'] is String) {
        final mentions = <String, String>{};
        final stored = data['mentions'];
        if (stored is Map) {
          for (final entry in stored.entries) {
            if (entry.key is String && entry.value is String) {
              mentions[entry.key] = entry.value;
            }
          }
        }
        Message? quote;
        try {
          if (data['quote'] is Map) {
            final value = Message.fromJson(
                Map<String, dynamic>.from(data['quote'] as Map));
            if (_canPersist(value)) quote = value;
          }
        } catch (_) {/* A damaged quote cannot discard valid draft text. */}
        return ChatDraft(data['text'] as String, mentions, quote);
      }
    } catch (_) {/* Plain SDK drafts predate the envelope. */}
    return ChatDraft(draft, const {}, null);
  }

  String encode() {
    final persistQuote = _canPersist(quote);
    if (text.isEmpty && !persistQuote) return '';
    return jsonEncode({
      'text': text,
      'mentions': mentions,
      if (persistQuote) 'quote': quote!.toJson(),
    });
  }
}
