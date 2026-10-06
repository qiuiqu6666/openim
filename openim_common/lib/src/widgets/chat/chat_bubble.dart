import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

enum BubbleType {
  send,
  receiver,
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    this.margin,
    this.compact = false,
    this.constraints,
    this.alignment = Alignment.center,
    this.backgroundColor,
    this.padding,
    this.borderRadius,
    this.child,
    required this.bubbleType,
  });
  final bool compact;
  final EdgeInsetsGeometry? margin;
  final BoxConstraints? constraints;
  final AlignmentGeometry? alignment;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Widget? child;
  final BubbleType bubbleType;

  bool get isISend => bubbleType == BubbleType.send;

  @override
  Widget build(BuildContext context) {
    final color = backgroundColor ??
        (isISend
            ? Styles.c_CCE7FE
            : ChatBubbleTokens.incoming(
                dark: Theme.of(context).brightness == Brightness.dark));
    final incomingBorder = !isISend &&
            ThemeData.estimateBrightnessForColor(color) == Brightness.light
        ? Border.all(
            color: ChatBubbleTokens.incomingBorder,
            width: ChatBubbleTokens.incomingBorderWidth,
          )
        : null;
    return Container(
      constraints: constraints,
      margin: margin,
      padding: padding ??
          (compact
              ? EdgeInsets.fromLTRB(10.w, 8.w, 10.w, 6.w)
              : EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h)),
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius ?? _defaultRadius(isISend),
        border: incomingBorder,
      ),
      child: child,
    );
  }
}

BorderRadius _defaultRadius(bool isISend) => borderRadius(isISend);
