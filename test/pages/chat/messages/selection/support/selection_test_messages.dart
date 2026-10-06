import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

Message selectionMessage(
  String id, {
  int contentType = MessageType.text,
  int status = MessageStatus.succeeded,
  String? customData,
  bool private = false,
  bool expired = false,
}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': contentType,
      'status': status,
      'sendID': 'sender',
      'recvID': 'peer',
      'senderNickname': '消息发送人',
      'sessionType': ConversationType.single,
      'sendTime': 1700000000000,
      'textElem': {'content': '消息 $id'},
      if (customData != null) 'customElem': {'data': customData},
      if (private || expired)
        'attachedInfoElem': {
          'isPrivateChat': true,
          if (expired) 'hasReadTime': 1700000000,
          if (expired) 'burnDuration': 1,
        },
    });

Message selectionClaimNotice(String id) => selectionMessage(
      id,
      contentType: MessageType.custom,
      customData: jsonEncode({
        'businessID': 'fund_packet_claim_notice',
        'orderID': 'packet-order',
        'claimerID': 'sender',
        'senderID': 'packet-sender',
      }),
    );
