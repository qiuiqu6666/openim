import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Ordinary-message APNs metadata. Notification text never includes the body.
class APNsOfflinePushInfo {
  APNsOfflinePushInfo._();

  static OfflinePushInfo generic() => OfflinePushInfo(
        title: '99CHAT',
        desc: '你收到了一条新消息',
        iOSBadgeCount: true,
        iOSPushSound: 'default',
      );

  static OfflinePushInfo chatMessage({
    required String sendID,
    required int sessionType,
    String? groupID,
  }) {
    final group = groupID ?? '';
    final single = sessionType == ConversationType.single;
    // 2 is the SDK's supported legacy group conversation value.
    final groupChat =
        sessionType == 2 || sessionType == ConversationType.superGroup;
    if (!validIdentifier(sendID) ||
        (!single && !groupChat) ||
        (single ? group.isNotEmpty : !validIdentifier(group))) {
      throw const FormatException('Invalid offline message destination');
    }
    return generic()
      ..ex = jsonEncode({
        'version': 1,
        'type': 'chat_message',
        'sessionType': sessionType,
        'sendID': sendID,
        'groupID': group,
      });
  }

  static bool validIdentifier(String value) =>
      value.isNotEmpty &&
      value == value.trim() &&
      !RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value);

  /// Read the destination group, never the forwarded source message's type.
  static int? sessionTypeForGroup(GroupInfo group) => switch (group.groupType) {
        0 => 2, // SDK GroupType.general -> ConversationType.group.
        GroupType.work => ConversationType.superGroup,
        _ => null,
      };

  static int? sessionTypeForSelection(Object? selection) {
    if (selection is ConversationInfo) return selection.conversationType;
    if (selection is GroupInfo) return sessionTypeForGroup(selection);
    return null;
  }
}
