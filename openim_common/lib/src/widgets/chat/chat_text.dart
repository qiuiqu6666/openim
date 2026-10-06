import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

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
    if (enableMarkdown && ChatMarkdownText.hasMarkdown(text)) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maximumWidth ?? maxWidth),
        child: ChatMarkdownText(
          text: text,
          textStyle: textStyle ?? Styles.ts_0C1C33_17sp,
          matchTextStyle: matchTextStyle ?? Styles.ts_0089FF_17sp,
          patterns: patterns,
          textScaler: textScaler ??
              (textScaleFactor == 1
                  ? MediaQuery.textScalerOf(context)
                  : _ChatTextScaler(
                      MediaQuery.textScalerOf(context), textScaleFactor)),
          onVisibleTrulyText: onVisibleTrulyText,
        ),
      );
    }
    return MatchTextView(
      text: text,
      textStyle: textStyle ?? Styles.ts_0C1C33_17sp,
      matchTextStyle: matchTextStyle ?? Styles.ts_0089FF_17sp,
      maximumWidth: maximumWidth,
      textScaler: textScaler,
      prefixSpan: prefixSpan,
      textAlign: textAlign,
      overflow: overflow,
      textScaleFactor: textScaleFactor,
      patterns: patterns,
      model: model,
      maxLines: maxLines,
      onVisibleTrulyText: onVisibleTrulyText,
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
