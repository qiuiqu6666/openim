import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class UnreadCountView extends StatelessWidget {
  const UnreadCountView({
    super.key,
    this.count = 0,
    this.size = 13,
    this.fontSize = 8,
    this.margin,
    this.backgroundColor,
    this.foregroundColor,
    this.pill = false,
  })  : _compact = false,
        borderColor = null;

  /// Flat, content-width badge for compact icon lanes such as navigation.
  const UnreadCountView.compact({
    super.key,
    this.count = 0,
    this.margin,
    this.borderColor,
    this.backgroundColor,
    this.foregroundColor,
    this.pill = false,
  })  : size = 16,
        fontSize = 10,
        _compact = true;

  final bool _compact;
  /// Custom neutral badges omit the default red glow.
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool pill;
  final Color? borderColor;
  final int count;
  final double size;
  final double fontSize;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: count > 0,
      child: Container(
        alignment: pill ? null : Alignment.center,
        margin: margin,
        padding: pill
            ? EdgeInsets.symmetric(horizontal: 4.w)
            : _compact
            ? const EdgeInsets.symmetric(horizontal: 3)
            : count > 99
                ? EdgeInsets.symmetric(horizontal: 4.w)
                : null,
        constraints: BoxConstraints(
            minHeight: pill ? size : 0, maxHeight: size, minWidth: size),
        decoration: _decoration,
        child: pill
            ? Align(widthFactor: 1, heightFactor: 1, child: _text)
            : _text,
      ),
    );
  }

  Text get _text => Text(
        '${count > 99 ? '99+' : count}',
        maxLines: _compact || pill ? 1 : null,
        softWrap: !(_compact || pill),
        style: TextStyle(
          fontSize: _compact ? fontSize : fontSize.sp,
          color: foregroundColor ?? AppTokens.onAccent,
          fontWeight: _compact ? FontWeight.w600 : null,
          height: _compact ? 1 : null,
        ),
        textAlign: TextAlign.center,
      );

  Decoration get _decoration => _compact
      ? BoxDecoration(
          color: backgroundColor ?? Styles.c_FF381F,
          borderRadius: BorderRadius.circular(size / 2),
          border: borderColor == null
              ? null
              : Border.all(color: borderColor!, width: 1.5),
        )
      : BoxDecoration(
          color: backgroundColor ?? Styles.c_FF381F,
          shape: pill || count > 99 ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: pill
              ? BorderRadius.circular(size / 2)
              : count > 99 ? BorderRadius.circular(10.r) : null,
          boxShadow: backgroundColor != null ? null : [
            BoxShadow(
              color: const Color(0x26C61B4A),
              offset: Offset(1.15.w, 1.15.h),
              blurRadius: 57.58.r,
            ),
            BoxShadow(
              color: const Color(0x1AC61B4A),
              offset: Offset(2.3.w, 2.3.h),
              blurRadius: 11.52.r,
            ),
            BoxShadow(
              color: const Color(0x0DC61B4A),
              offset: Offset(4.61.w, 4.61.h),
              blurRadius: 17.28.r,
            ),
          ],
        );
}
