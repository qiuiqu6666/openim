import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../notifications/message_notification_target.dart';

/// A remote destination still awaiting authoritative SDK conversation data.
/// The session fingerprint always comes from the receiving client.
class ApnsNotificationTarget {
  const ApnsNotificationTarget._({
    required this.accountID,
    required this.sessionKey,
    required this.sourceID,
    required this.sessionType,
    required this.messageID,
    this.conversationID,
  });

  final String accountID, sessionKey, sourceID;
  final int sessionType;
  final String? messageID, conversationID;

  // Used only as an SDK lookup argument, never as a navigation destination.
  MessageNotificationTarget get lookup => MessageNotificationTarget(
        accountID: accountID,
        sessionKey: sessionKey,
        conversationID: conversationID ?? 'lookup',
        sourceID: sourceID,
        sessionType: sessionType,
        messageID: messageID,
      );

  MessageNotificationTarget? resolve(ConversationInfo conversation) {
    if (conversationID != null &&
        conversationID != conversation.conversationID) {
      return null;
    }
    final target = MessageNotificationTarget(
      accountID: accountID,
      sessionKey: sessionKey,
      conversationID: conversation.conversationID,
      sourceID: sourceID,
      sessionType: sessionType,
      messageID: messageID,
    );
    return target.matches(conversation) ? target : null;
  }
}

/// OpenIM APNs places the recipient/message identity outside its JSON `ex`.
/// Legacy canonical destinations remain readable with an explicit recipient.
ApnsNotificationTarget? apnsNotificationTarget(Map<String, dynamic> payload,
    {required String accountID, required String sessionKey}) {
  if (!_validID(accountID) || !_validID(sessionKey)) return null;
  final body = _body(payload);
  if (body == null) return null;
  final owner = body['accountID'] ?? body['recipientUserID'];
  if (owner is! String || owner != accountID) return null;

  if (body.containsKey('ex')) {
    if (body['accountID'] != accountID) return null;
    final ex = body['ex'];
    if (ex is! String) return null;
    final data = _map(ex);
    final message = body['clientMsgID'];
    if (data == null ||
        data['version'] is! int ||
        data['version'] != 1 ||
        data['type'] != 'chat_message' ||
        message is! String ||
        !_validID(message)) {
      return null;
    }
    final type = data['sessionType'];
    final sender = data['sendID'];
    final group = data['groupID'];
    if (type is! int ||
        !const [ConversationType.single, 2, ConversationType.superGroup]
            .contains(type) ||
        sender is! String ||
        !_validID(sender) ||
        group is! String ||
        (type == ConversationType.single
            ? group.isNotEmpty || sender == owner
            : !_validID(group))) {
      return null;
    }
    return ApnsNotificationTarget._(
      accountID: owner,
      sessionKey: sessionKey,
      sourceID: type == ConversationType.single ? sender : group,
      sessionType: type,
      messageID: message,
    );
  }

  final conversation = body['conversationID'];
  final source = body['sourceID'];
  final type = body['sessionType'];
  final message = body['clientMsgID'] ?? body['messageID'];
  if (conversation is! String ||
      source is! String ||
      type is! int ||
      (message != null && message is! String)) {
    return null;
  }
  final target = ApnsNotificationTarget._(
    accountID: owner,
    sessionKey: sessionKey,
    conversationID: conversation,
    sourceID: source,
    sessionType: type,
    messageID: message as String?,
  );
  return target.lookup.isValid ? target : null;
}

/// An unrecognized route can return only its verified recipient's message list.
bool apnsNotificationBelongsToAccount(Map<String, dynamic> payload,
    {required String accountID}) {
  final body = _body(payload);
  if (body == null || !_validID(accountID)) return false;
  final owner = body.containsKey('ex')
      ? body['accountID']
      : body['accountID'] ?? body['recipientUserID'];
  return owner is String && owner == accountID;
}

Map<String, dynamic>? _body(Map<String, dynamic> payload) {
  // Preserve recipient ownership on the actual top-level OpenIM contract.
  if (payload.containsKey('ex')) return payload;
  return payload.containsKey('data') ? _map(payload['data']) : payload;
}

Map<String, dynamic>? _map(Object? raw) {
  try {
    if (raw is String) raw = jsonDecode(raw);
    if (raw is! Map || raw.keys.any((key) => key is! String)) return null;
    return Map<String, dynamic>.from(raw);
  } on FormatException {
    return null;
  }
}

bool _validID(String value) => value.isNotEmpty && value.trim() == value;
