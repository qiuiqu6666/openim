import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../res/typography/chat_message_typography.dart';

class ChatText extends StatelessWidget {
  const ChatText({
    super.key,
    this.isISend = false,
    required this.text,
    this.prefixSpan,
    this.patterns = const <MatchPattern>[],
    this.textAlign = TextAlign.left,
    this.overflow = TextOverflow.clip,
    this.textStyle,
    this.matchTextStyle,
    this.maximumWidth,
    this.textScaler,
    this.maxLines,
    this.textScaleFactor = 1.0,
    this.model = TextModel.match,
    this.enableMarkdown = false,
    this.onVisibleTrulyText,
  });
  final bool isISend;
  final String text;
  final TextStyle? textStyle;
  final TextStyle? matchTextStyle;
  final double? maximumWidth;
  final TextScaler? textScaler;
  final InlineSpan? prefixSpan;
  final TextAlign textAlign;
  final TextOverflow overflow;
  final int? maxLines;
  final double textScaleFactor;
  final List<MatchPattern> patterns;
  final TextModel model;

  /// Opt in for message bodies; captions and compact previews remain plain.
  final bool enableMarkdown;
  final Function(String? text)? onVisibleTrulyText;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bodyStyle = (textStyle ?? chatMessageTextStyle(context)).copyWith(
      height: textStyle?.height ?? ChatBubbleTokens.textLineHeight,
    );
    final linkStyle = (matchTextStyle ??
            bodyStyle.copyWith(
              color: dark && isISend ? AppTokens.onAccent : Styles.c_0089FF,
            ))
        .copyWith(
      height: matchTextStyle?.height ?? bodyStyle.height,
    );
    final scaler = textScaler ??
        (textScaleFactor == 1
            ? MediaQuery.textScalerOf(context)
            : _ChatTextScaler(
                MediaQuery.textScalerOf(context), textScaleFactor));
    if (enableMarkdown && ChatMarkdownText.hasMarkdown(text)) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maximumWidth ?? maxWidth),
        child: ChatMarkdownText(
          text: text,
          textStyle: bodyStyle,
          matchTextStyle: linkStyle,
          patterns: patterns,
          textScaler: scaler,
          onVisibleTrulyText: onVisibleTrulyText,
        ),
      );
    }
    return DefaultTextStyle.merge(
      style: bodyStyle,
      child: MatchTextView(
        text: text,
        textStyle: bodyStyle,
        matchTextStyle: linkStyle,
        maximumWidth: maximumWidth,
        textScaler: scaler,
        prefixSpan: prefixSpan,
        textAlign: textAlign,
        overflow: overflow,
        textScaleFactor: textScaleFactor,
        patterns: patterns,
        model: model,
        maxLines: maxLines,
        onVisibleTrulyText: onVisibleTrulyText,
      ),
    );
  }
}

/// Apply the chat preference before the system's potentially nonlinear scale.
class _ChatTextScaler extends TextScaler {
  const _ChatTextScaler(this.system, this.factor);

  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize * factor);

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is _ChatTextScaler &&
      system == other.system &&
      factor == other.factor;

  @override
  int get hashCode => Object.hash(system, factor);
}
