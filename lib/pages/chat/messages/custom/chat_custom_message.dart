import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';

import '../../fund/fund_message_card.dart';
import '../../../ai_assistant/presentation/messages/ai_openim_custom_message.dart';
import 'custom_message_text.dart';

/// Shared presentation for the chat timeline and its read-only peek.
/// Live order status and relationship actions remain owned by the chat route.
CustomTypeInfo buildChatCustomMessage(
  BuildContext context,
  Message message, {
  required bool isGroupChat,
  String peerName = '',
  VoidCallback? onFriendVerification,
  double textScaleFactor = 1,
}) {
  final fund = FundMessageData.tryParse(message.customElem?.data);
  if (fund != null) {
    return CustomTypeInfo(
      FundMessageCard(
        message: fund,
        isGroupChat: isGroupChat,
        isOutgoing: message.sendID == OpenIM.iMManager.userID,
        timeText: message.sendTime == null
            ? ''
            : DateFormat('HH:mm')
                .format(DateTime.fromMillisecondsSinceEpoch(message.sendTime!)),
        statusResolved: false,
      ),
      false,
    );
  }
  final data = IMUtils.parseCustomMessage(message);
  final type = data?['viewType'];
  if (type == CustomMessageType.call) {
    return CustomTypeInfo(
        ChatCallItemView(type: data['type'], content: data['content']));
  }
  if (type == CustomMessageType.deletedByFriend ||
      type == CustomMessageType.blockedByFriend) {
    return CustomTypeInfo(
      ChatFriendRelationshipAbnormalHintView(
        name: peerName,
        onTap: onFriendVerification,
        blockedByFriend: type == CustomMessageType.blockedByFriend,
        deletedByFriend: type == CustomMessageType.deletedByFriend,
      ),
      false,
      false,
    );
  }
  if (type == CustomMessageType.removedFromGroup ||
      type == CustomMessageType.groupDisbanded) {
    return CustomTypeInfo(
      Text(
        type == CustomMessageType.removedFromGroup
            ? StrRes.removedFromGroupHint
            : StrRes.groupDisbanded,
        textAlign: TextAlign.center,
        style: Styles.ts_8E9AB0_12sp
            .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      false,
      false,
    );
  }
  final assistant = buildAiOpenIMCustomMessage(context, message);
  if (assistant != null) return assistant;
  final text = customMessageText(
      message.customElem?.data, message.customElem?.description);
  return CustomTypeInfo(ChatText(
    text: text.isEmpty ? StrRes.unsupportedMessage : text,
    enableMarkdown: true,
    textScaleFactor: textScaleFactor,
  ));
}
