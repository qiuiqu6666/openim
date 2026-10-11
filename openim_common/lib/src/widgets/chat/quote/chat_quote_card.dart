import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_quote_content.dart';
import 'chat_quote_tokens.dart';

class ChatQuoteCard extends StatelessWidget {
  const ChatQuoteCard(
      {super.key,
      required this.message,
      required this.bubbleColor,
      this.onTap});
  final Message? message;
  final Color bubbleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        onTapHint: onTap == null ? null : '定位原消息',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ClipRRect(
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
          ),
        ),
      );
}
