import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../models/call_types.dart';

/// The same live surface is used by the app float and Android system PiP.
class CallCompactSurface extends StatelessWidget {
  const CallCompactSurface(
      {super.key,
      this.userInfo,
      required this.state,
      required this.duration,
      this.video,
      this.systemPip = false});
  final UserInfo? userInfo;
  final CallState state;
  final int duration;
  final Widget? video;
  final bool systemPip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = state == CallState.calling
        ? IMUtils.seconds2HMS(duration)
        : state == CallState.connecting
            ? StrRes.connecting
            : StrRes.waitingVoiceCallHint;
    return Material(
      color: colors.surfaceContainerHigh,
      child: LayoutBuilder(
          builder: (context, constraints) => Stack(children: [
                // The float owns restore/drag gestures. Local camera renderers
                // also recognize focus/zoom, which must not compete here.
                if (video != null)
                  Positioned.fill(child: IgnorePointer(child: video!)),
                if (video == null)
                  Center(
                      child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth.isFinite
                                    ? (constraints.maxWidth - 16)
                                        .clamp(0, double.infinity)
                                    : 200),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call_rounded,
                                    size: 32, color: colors.primary),
                                const SizedBox(height: 8),
                                Text(label,
                                    style:
                                        Theme.of(context).textTheme.labelMedium,
                                    maxLines: 1),
                                if (systemPip && userInfo != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                          userInfo!.remark ??
                                              userInfo!.nickname ??
                                              '',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                              ],
                            ))),
                  )),
                if (video != null)
                  Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Styles.c_FFFFFF, shadows: [
                            Shadow(color: Styles.c_000000, blurRadius: 4)
                          ]))),
              ])),
    );
  }
}
