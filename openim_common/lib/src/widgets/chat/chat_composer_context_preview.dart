import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_composer_palette.dart';
import 'quote/chat_quote_content.dart';
import 'quote/chat_quote_tokens.dart';

class ChatComposerContextPreview extends StatelessWidget {
  const ChatComposerContextPreview({
    super.key,
    this.onClose,
    this.message,
    this.content,
    this.textSpan,
  }) : assert(message != null || content != null || textSpan != null,
            'A message, content or textSpan must be provided.');
  final VoidCallback? onClose;
  final Message? message;
  final String? content;
  final InlineSpan? textSpan;

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
        child: Material(
          color: chatComposerSurface(context),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppTokens.s3, AppTokens.s2, 0, AppTokens.s2),
            child: Row(children: [
              Expanded(
                  child: message != null
                      ? ChatQuoteContent(
                          message: message,
                          replyLabel: true,
                          titleColor: AppTokens.accent,
                          summaryColor: chatComposerHint(context))
                      : Text.rich(textSpan ?? TextSpan(text: content),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: chatComposerTextStyle(context).copyWith(
                              color: chatComposerHint(context),
                              fontSize: ChatQuoteTokens.summarySize))),
              IconButton(
                key: const ValueKey('chat-context-preview-close'),
                onPressed: onClose,
                tooltip: message == null
                    ? StrRes.cancel
                    : '${StrRes.cancel} ${StrRes.reply}',
                color: chatComposerHint(context),
                constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension),
                visualDensity: VisualDensity.standard,
                icon: const Icon(Icons.cancel,
                    size: ChatQuoteTokens.closeIconSize),
              ),
            ]),
          ),
        ),
      );
}
