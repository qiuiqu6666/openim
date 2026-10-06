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
  });
  final String text;
  final String icon;
  final Function()? onTap;
  final Color? foreground;

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
                padding: const EdgeInsets.all(4),
                child: Opacity(
                    opacity: onTap == null ? .4 : 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon.toImage
                          ..width = 62.w
                          ..height = 62.w,
                        10.verticalSpace,
                        Text(text,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: foreground ??
                                        Theme.of(context)
                                            .colorScheme
                                            .onSurface)),
                      ],
                    )))));
  }

  LiveButton.microphone({
    super.key,
    this.foreground,
    this.onTap,
    bool on = true,
  })  : text = StrRes.microphone,
        icon = on ? ImageRes.liveMicOn : ImageRes.liveMicOff;

  LiveButton.speaker({
    super.key,
    this.foreground,
    this.onTap,
    bool on = true,
  })  : text = StrRes.speaker,
        icon = on ? ImageRes.liveSpeakerOn : ImageRes.liveSpeakerOff;

  LiveButton.hungUp({
    super.key,
    this.foreground,
    this.onTap,
  })  : text = StrRes.hangUp,
        icon = ImageRes.liveHangUp;

  LiveButton.reject({
    super.key,
    this.foreground,
    this.onTap,
  })  : text = StrRes.reject,
        icon = ImageRes.liveHangUp;

  LiveButton.cancel({
    super.key,
    this.foreground,
    this.onTap,
  })  : text = StrRes.cancel,
        icon = ImageRes.liveHangUp;

  LiveButton.pickUp({
    super.key,
    this.foreground,
    this.onTap,
  })  : text = StrRes.pickUp,
        icon = ImageRes.livePicUp;
}
