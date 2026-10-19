import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';

import 'confirmed_fund_cards.dart';
import 'fund_card_recipient.dart';
import 'fund_message_card.dart';

class ConfirmedFundCardRow extends StatelessWidget {
  const ConfirmedFundCardRow(
      {super.key,
      required this.card,
      required this.onTap,
      required this.isGroup,
      required this.packetCount,
      required this.claimedByMe,
      required this.recipient});
  final ConfirmedFundCard card;
  final VoidCallback onTap;
  final bool isGroup;
  final FundCardRecipient recipient;
  final int? packetCount;
  final bool claimedByMe;

  @override
  Widget build(BuildContext context) => ChatItemContainer(
        id: card.id,
        isISend: true,
        isBubbleBg: false,
        bareMedia: true,
        metadataBelow: true,
        hasRead: false,
        showReadStatus: false,
        showStatus: false,
        isSending: false,
        isSendFailed: false,
        avatarSize: 36,
        rightNickname: OpenIM.iMManager.userInfo.nickname,
        rightFaceUrl: OpenIM.iMManager.userInfo.faceURL,
        child: GestureDetector(
          onTap: onTap,
          child: FundMessageCard(
            message: card.data,
            isOutgoing: true,
            isGroupChat: isGroup,
            recipient: recipient,
            packetCount: packetCount,
            claimedByMe: claimedByMe,
            timeText: card.order.createdAt == null
                ? ''
                : DateFormat('HH:mm').format(card.order.createdAt!),
          ),
        ),
      );
}
