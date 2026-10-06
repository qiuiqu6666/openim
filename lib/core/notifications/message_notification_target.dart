import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// The destination and owning login session of a native message notification.
/// [sessionKey] is an opaque session fingerprint supplied by the app, never a
/// raw login token. SDK conversation data remains authoritative when acted on.
class MessageNotificationTarget {
  const MessageNotificationTarget({
    required this.accountID,
    required this.sessionKey,
    required this.conversationID,
    required this.sourceID,
    required this.sessionType,
    this.messageID,
  });

  static const _version = 1;
  // SDK v3 deprecates this constant, but existing v2 conversation IDs persist.
  static const _legacyGroup = 2;
  static const _fields = {
    'version',
    'accountID',
    'sessionKey',
    'conversationID',
    'sourceID',
    'sessionType',
  };

  final String accountID;
  final String sessionKey;
  final String conversationID;
  final String sourceID;
  final int sessionType;
  // Native notification IDs are stable per conversation. This identifies which
  // incoming message the user replied to when that notification is replaced.
  final String? messageID;

  bool get isSingleChat => sessionType == ConversationType.single;

  bool get isValid =>
      _validID(accountID) &&
      _validID(sessionKey) &&
      _validID(conversationID) &&
      _validID(sourceID) &&
      (messageID == null || _validID(messageID!)) &&
      (isSingleChat ||
          sessionType == _legacyGroup ||
          sessionType == ConversationType.superGroup);

  String encode() {
    if (!isValid) {
      throw ArgumentError('Invalid message notification destination');
    }
    return jsonEncode({
      'version': _version,
      'accountID': accountID,
      'sessionKey': sessionKey,
      'conversationID': conversationID,
      'sourceID': sourceID,
      'sessionType': sessionType,
      if (messageID != null) 'messageID': messageID,
    });
  }

  static MessageNotificationTarget? decode(String? payload) {
    if (payload == null || payload.isEmpty || payload.length > 8192) {
      return null;
    }
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, dynamic> ||
          !_fields.every(value.containsKey) ||
          !value.keys
              .every((key) => _fields.contains(key) || key == 'messageID') ||
          value['version'] is! int ||
          value['version'] != _version ||
          value['accountID'] is! String ||
          value['sessionKey'] is! String ||
          value['conversationID'] is! String ||
          value['sourceID'] is! String ||
          value['sessionType'] is! int ||
          (value.containsKey('messageID') && value['messageID'] is! String)) {
        return null;
      }
      final target = MessageNotificationTarget(
        accountID: value['accountID'] as String,
        sessionKey: value['sessionKey'] as String,
        conversationID: value['conversationID'] as String,
        sourceID: value['sourceID'] as String,
        sessionType: value['sessionType'] as int,
        messageID: value['messageID'] as String?,
      );
      return target.isValid ? target : null;
    } on FormatException {
      return null;
    }
  }

  /// A payload must not redirect to another SDK conversation or destination.
  bool matches(ConversationInfo conversation) =>
      isValid &&
      conversation.conversationID == conversationID &&
      conversation.conversationType == sessionType &&
      (isSingleChat
          ? conversation.userID == sourceID &&
              (conversation.groupID ?? '').isEmpty
          : conversation.groupID == sourceID &&
              (conversation.userID ?? '').isEmpty);

  static bool _validID(String value) =>
      value.isNotEmpty && value.trim() == value;
}
