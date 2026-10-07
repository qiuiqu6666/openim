import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_quote_thumbnail.dart';
import 'chat_quote_tokens.dart';

String chatQuoteSummary(Message? message) {
  if (message == null) return StrRes.message;
  if (message.hasExpired) return IMUtils.parseMsg(message);
  if (message.isPictureType) return StrRes.picture;
  if (message.isVideoType) return StrRes.video;
  final fund = FundMessageData.tryParse(message.customElem?.data);
  final summary = fund?.isPacket == true
      ? '[${fund!.typeLabel}] ${fund.remark}'
      : IMUtils.parseMsg(message);
  final normalized = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.isEmpty ? StrRes.message : normalized;
}

/// Shared message summary for the composer preview and sent quote card.
class ChatQuoteContent extends StatelessWidget {
  const ChatQuoteContent(
      {super.key,
      required this.message,
      required this.titleColor,
      required this.summaryColor,
      this.replyLabel = false});
  final Message? message;
  final Color titleColor;
  final Color summaryColor;
  final bool replyLabel;

  @override
  Widget build(BuildContext context) {
    final name = message?.senderNickname?.trim() ?? '';
    final sender = name.isNotEmpty ? name : message?.sendID ?? StrRes.message;
    final title = replyLabel ? '${StrRes.reply} $sender' : sender;
    final summary = chatQuoteSummary(message);
    return Row(children: [
      if (ChatQuoteThumbnail.supports(message)) ...[
        ChatQuoteThumbnail(
            key: ValueKey(message!.clientMsgID), message: message!),
        const SizedBox(width: AppTokens.s3),
      ],
      Expanded(
          child: Tooltip(
              message: '$title\n$summary',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: titleColor,
                          fontSize: ChatQuoteTokens.titleSize,
                          height: ChatQuoteTokens.lineHeight,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: ChatQuoteTokens.titleGap),
                  Text(summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: summaryColor,
                          fontSize: ChatQuoteTokens.summarySize,
                          height: ChatQuoteTokens.lineHeight)),
                ],
              ))),
    ]);
  }
}
