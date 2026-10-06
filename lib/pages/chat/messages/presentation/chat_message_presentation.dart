import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Stateless display policies shared by the chat's message rows.
class ChatMessagePresentation {
  static bool isNotification(Message message) => message.contentType! >= 1000;

  static bool isFailedHint(Message message) {
    if (message.contentType == MessageType.custom) {
      final data = message.customElem!.data;
      final map = json.decode(data!);
      final customType = map['customType'];
      return customType == CustomMessageType.deletedByFriend ||
          customType == CustomMessageType.blockedByFriend;
    }
    return false;
  }

  static bool showBubbleBackground(Message message) =>
      !isNotification(message) && !isFailedHint(message);
}
