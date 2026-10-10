import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Converts an accepted SDK recall into a content-free timeline notice.
class ChatRevocationNotice {
  static Message replace(Message source, RevokedInfo info) => Message(
        clientMsgID: source.clientMsgID,
        serverMsgID: source.serverMsgID,
        sendTime: source.sendTime,
        createTime: source.createTime,
        seq: source.seq,
        sendID: source.sendID,
        recvID: source.recvID,
        groupID: source.groupID,
        sessionType: source.sessionType,
        status: MessageStatus.succeeded,
        contentType: MessageType.revokeMessageNotification,
        notificationElem: NotificationElem(detail: jsonEncode(info.toJson())),
      );

  static String text(Message message, String selfID) {
    try {
      final data = jsonDecode(message.notificationElem?.detail ?? '{}');
      final info = RevokedInfo.fromJson(Map<String, dynamic>.from(data));
      if (info.revokerID == 'imAdmin' ||
          info.revokerNickname?.trim() == 'imAdmin') {
        return '管理员撤回了一条消息';
      }
      if (info.revokerID == selfID && selfID.isNotEmpty) {
        return '你撤回了一条消息';
      }
      final name = info.revokerNickname?.trim() ?? '';
      return name.isEmpty ? '一条消息已被撤回' : '$name撤回了一条消息';
    } catch (_) {
      return '一条消息已被撤回';
    }
  }
}
