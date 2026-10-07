import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_quote_content.dart';
import 'chat_quote_tokens.dart';

class ChatQuoteCard extends StatelessWidget {
  const ChatQuoteCard(
      {super.key, required this.message, required this.bubbleColor});
  final Message? message;
  final Color bubbleColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(ChatQuoteTokens.cardRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ChatQuoteTokens.background(bubbleColor),
            border: BorderDirectional(
                start: BorderSide(
              color: ChatQuoteTokens.border(bubbleColor),
              width: ChatQuoteTokens.borderWidth,
            )),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s3,
                vertical: ChatQuoteTokens.cardVerticalPadding),
            child: ChatQuoteContent(
                message: message,
                titleColor: ChatQuoteTokens.sender(bubbleColor),
                summaryColor: ChatQuoteTokens.summary(bubbleColor)),
          ),
        ),
      );
}
