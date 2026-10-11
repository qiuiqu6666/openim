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
  })  : _compact = false,
        borderColor = null;

  /// Flat, content-width badge for compact icon lanes such as navigation.
  const UnreadCountView.compact({
    super.key,
    this.count = 0,
    this.margin,
    this.borderColor,
  })  : size = 16,
        fontSize = 10,
        _compact = true;

  final bool _compact;
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
        alignment: Alignment.center,
        margin: margin,
        padding: _compact
            ? const EdgeInsets.symmetric(horizontal: 3)
            : count > 99
                ? EdgeInsets.symmetric(horizontal: 4.w)
                : null,
        constraints: BoxConstraints(maxHeight: size, minWidth: size),
        decoration: _decoration,
        child: _text,
      ),
    );
  }

  Text get _text => Text(
        '${count > 99 ? '99+' : count}',
        maxLines: _compact ? 1 : null,
        softWrap: !_compact,
        style: TextStyle(
          fontSize: _compact ? fontSize : fontSize.sp,
          color: AppTokens.onAccent,
          fontWeight: _compact ? FontWeight.w600 : null,
          height: _compact ? 1 : null,
        ),
        textAlign: TextAlign.center,
      );

  Decoration get _decoration => _compact
      ? BoxDecoration(
          color: AppTokens.danger,
          borderRadius: BorderRadius.circular(size / 2),
          border: borderColor == null
              ? null
              : Border.all(color: borderColor!, width: 1.5),
        )
      : BoxDecoration(
          color: Styles.c_FF381F,
          shape: count > 99 ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: count > 99 ? BorderRadius.circular(10.r) : null,
          boxShadow: [
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
