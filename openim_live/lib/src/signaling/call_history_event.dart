import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

class SignalingMessageEvent {
  SignalingMessageEvent(
      this.message, this.sessionType, this.userID, this.groupID);
  Message message;
  String? userID;
  String? groupID;
  int sessionType;
  bool get isSingleChat => sessionType == ConversationType.single;
  bool get isGroupChat =>
      sessionType == ConversationType.group ||
      sessionType == ConversationType.superGroup;
}

extension MessageMangerExt on MessageManager {
  Future<Message> createCallMessage(
          {required String type,
          required String state,
          int? duration,
          String? roomID}) =>
      createCustomMessage(
        data: jsonEncode({
          'customType': CustomMessageType.call,
          'data': {
            'roomID': roomID,
            'duration': duration,
            'state': state,
            'type': type
          }
        }),
        extension: '',
        description: '',
      );
}
