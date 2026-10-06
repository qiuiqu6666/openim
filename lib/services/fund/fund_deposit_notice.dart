import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../pages/official_account/models/official_account.dart';

/// A notification is a refresh hint, never a balance or proof of credit.
String? fundDepositNoticeID(Message message, {String? receiverID}) {
  if (message.contentType != MessageType.text ||
      message.sendID != OfficialAccount.payUserID ||
      message.sessionType != ConversationType.single ||
      (receiverID != null &&
          message.recvID != null &&
          message.recvID!.isNotEmpty &&
          message.recvID != receiverID)) {
    return null;
  }
  try {
    final data = jsonDecode(message.ex ?? '');
    final value = data is Map ? data['depositNoticeID'] : null;
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  } on FormatException {
    return null;
  }
}
