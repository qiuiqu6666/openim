import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class Button extends StatelessWidget {
  const Button({
    super.key,
    required this.text,
    this.enabled = true,
    this.loading = false,
    this.enabledColor,
    this.disabledColor,
    this.radius,
    this.textStyle,
    this.disabledTextStyle,
    this.onTap,
    this.height,
    this.margin,
    this.padding,
    this.border,
    this.gradient,
    this.trailingIcon,
  });
  final Color? enabledColor;
  final Color? disabledColor;
  final double? radius;
  final TextStyle? textStyle;
  final TextStyle? disabledTextStyle;
  final String text;
  final double? height;
  final Function()? onTap;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final bool enabled;
  final bool loading;
  final BoxBorder? border;
  final Gradient? gradient;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && !loading;
    final effectiveTextStyle = isEnabled
        ? textStyle ?? Styles.ts_FFFFFF_17sp_semibold
        : disabledTextStyle ?? textStyle ?? Styles.ts_FFFFFF_17sp_semibold;
    final foreground = effectiveTextStyle.foreground?.color ??
        effectiveTextStyle.color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onPrimary;
    final label = Text(
      text,
      style: effectiveTextStyle,
      textAlign: TextAlign.center,
    );
    return Container(
      margin: margin,
      child: Semantics(
        button: true,
        enabled: isEnabled,
        liveRegion: loading,
        onTap: isEnabled && onTap != null ? () => onTap!() : null,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              border: border,
              color: gradient == null
                  ? isEnabled
                      ? enabledColor ?? Styles.c_0089FF
                      : disabledColor ?? Styles.c_0089FF_opacity50
                  : null,
              gradient: isEnabled ? gradient : gradient?.scale(.85),
              borderRadius: BorderRadius.circular(radius ?? 4.r),
            ),
            child: InkWell(
              onTap: isEnabled ? onTap : null,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(radius ?? 4.r),
              child: Container(
                constraints: BoxConstraints(minHeight: height ?? 44.h),
                padding: padding,
                child: Align(
                  heightFactor: 1,
                  child: loading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ExcludeSemantics(
                              child: SizedBox.square(
                                dimension: AppTokens.s6,
                                child: CircularProgressIndicator(
                                  strokeWidth: AppTokens.s2 / 2,
                                  color: foreground,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTokens.s3),
                            Flexible(child: label),
                          ],
                        )
                      : trailingIcon == null
                          ? label
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(child: label),
                                const SizedBox(width: AppTokens.s3),
                                ExcludeSemantics(
                                  child: Icon(
                                    trailingIcon,
                                    size: AppTokens.chevronSize,
                                    color: foreground,
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ImageTextButton extends StatelessWidget {
  const ImageTextButton({
    super.key,
    required this.icon,
    required this.text,
    this.textStyle,
    this.color,
    this.height,
    this.onTap,
  });
  final String icon;
  final String text;
  final TextStyle? textStyle;
  final Color? color;
  final double? height;
  final Function()? onTap;

  ImageTextButton.call({super.key, this.onTap})
      : icon = ImageRes.audioAndVideoCall,
        text = StrRes.audioAndVideoCall,
        color = Styles.c_FFFFFF,
        textStyle = null,
        height = null;

  ImageTextButton.message({super.key, this.onTap})
      : icon = ImageRes.message,
        text = StrRes.sendMessage,
        color = Styles.c_0089FF,
        textStyle = Styles.ts_FFFFFF_17sp,
        height = null;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(6.r),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: height ?? 46.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6.r),
          color: color,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6.r),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon.toImage
                ..width = 20.w
                ..height = 20.h,
              6.horizontalSpace,
              text.toText..style = textStyle ?? Styles.ts_0C1C33_17sp,
            ],
          ),
        ),
      ),
    );
  }
}
