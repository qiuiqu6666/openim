// Adapted from 99chat's ui/widgets/chat_text_bubble_layout.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: receive the actual metadata style and keep SDK-independent inputs.
import '../../res/app_tokens.dart';

import 'package:flutter/material.dart';

/// Keeps metadata below the actual message body with a consistent gap.
class ChatTextBubbleLayout extends StatelessWidget {
  const ChatTextBubbleLayout({
    super.key,
    required this.text,
    required this.textStyle,
    required this.timeText,
    required this.metadataTextStyle,
    required this.body,
    required this.metadata,
    this.reserveReceipt = false,
    this.forceSeparateFooter = false,
  });

  final String text;
  final TextStyle textStyle;
  final String timeText;
  final TextStyle metadataTextStyle;
  final Widget body;
  final Widget metadata;
  final bool reserveReceipt;
  final bool forceSeparateFooter;

  @override
  Widget build(BuildContext context) {
    // Lay out the actual body instead of estimating its glyph metrics. Font
    // fallback, rich spans and chat text scaling can differ from TextPainter.
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        body,
        const SizedBox(height: AppTokens.s3),
        Align(alignment: Alignment.centerRight, child: metadata),
      ],
    );
    return forceSeparateFooter ? content : IntrinsicWidth(child: content);
  }
}
