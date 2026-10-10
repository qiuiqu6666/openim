import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class LiveButton extends StatelessWidget {
  const LiveButton({
    super.key,
    required this.text,
    required this.icon,
    this.onTap,
    this.foreground,
    this.iconSize,
    this.labelWidth,
    this.labelStyle,
    this.contentPadding = const EdgeInsets.all(4),
    this.labelSpacing,
  });
  final String text;
  final String icon;
  final Function()? onTap;
  final Color? foreground;
  final double? iconSize, labelWidth, labelSpacing;
  final TextStyle? labelStyle;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
        button: true,
        enabled: onTap != null,
        label: text,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
                padding: contentPadding,
                child: Opacity(
                    opacity: onTap == null ? .4 : 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon.toImage
                          ..width = iconSize ?? 62.w
                          ..height = iconSize ?? 62.w,
                        SizedBox(height: labelSpacing ?? 10.h),
                        SizedBox(
                          width: labelWidth,
                          child: Text(text,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: (labelStyle ??
                                      Theme.of(context).textTheme.labelMedium)
                                  ?.copyWith(
                                      color: foreground ??
                                          Theme.of(context)
                                              .colorScheme
                                              .onSurface)),
                        ),
                      ],
                    )))));
  }

  LiveButton.microphone({
    Key? key,
    Color? foreground,
    VoidCallback? onTap,
    bool on = true,
  }) : this(
            key: key,
            foreground: foreground,
            onTap: onTap,
            text: StrRes.microphone,
            icon: on ? ImageRes.liveMicOn : ImageRes.liveMicOff);

  LiveButton.speaker({
    Key? key,
    Color? foreground,
    VoidCallback? onTap,
    bool on = true,
  }) : this(
            key: key,
            foreground: foreground,
            onTap: onTap,
            text: StrRes.speaker,
            icon: on ? ImageRes.liveSpeakerOn : ImageRes.liveSpeakerOff);

  LiveButton.hungUp({
    Key? key,
    Color? foreground,
    VoidCallback? onTap,
  }) : this(
            key: key,
            foreground: foreground,
            onTap: onTap,
            text: StrRes.hangUp,
            icon: ImageRes.liveHangUp);

  LiveButton.reject({
    Key? key,
    Color? foreground,
    VoidCallback? onTap,
  }) : this(
            key: key,
            foreground: foreground,
            onTap: onTap,
            text: StrRes.reject,
            icon: ImageRes.liveHangUp);

  LiveButton.cancel({
    Key? key,
    Color? foreground,
    VoidCallback? onTap,
  }) : this(
            key: key,
            foreground: foreground,
            onTap: onTap,
            text: StrRes.cancel,
            icon: ImageRes.liveHangUp);

  LiveButton.pickUp({
    Key? key,
    Color? foreground,
    VoidCallback? onTap,
  }) : this(
            key: key,
            foreground: foreground,
            onTap: onTap,
            text: StrRes.pickUp,
            icon: ImageRes.livePicUp);
}
