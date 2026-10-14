import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'connection_badge_style.dart';
import 'connection_signal_icon.dart';

/// One live status from the reference's four-state visual legend.
class ConnectionLatencyBadge extends StatelessWidget {
  const ConnectionLatencyBadge(
      {super.key,
      required this.latencyMs,
      required this.failed,
      required this.checking,
      this.marker,
      this.textKey});

  final int? latencyMs;
  final bool failed, checking;
  final String? marker;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final measured = !failed && !checking ? latencyMs : null;
    final palette = ConnectionBadgeStyle.palette(measured, dark);
    final label = failed
        ? (chinese ? '不可用' : 'Unavailable')
        : measured == null
            ? (chinese ? '检测中' : 'Checking')
            : '$measured ms';
    final quality = failed
        ? (chinese ? '离线' : 'Offline')
        : measured == null
            ? (chinese ? '检测中' : 'Checking')
            : measured < 200
                ? (chinese ? '良好' : 'Good')
                : measured < 500
                    ? (chinese ? '一般' : 'Fair')
                    : (chinese ? '较高' : 'High');
    // The reference's offline capsule contains only the unavailable label.
    final suffix = measured == null || marker == null ? '' : ' · $marker';
    final routeDescription = marker == null ? '' : ' · $marker';
    return Tooltip(
      message: chinese
          ? '$quality$routeDescription · 当前线路 API 响应耗时，约每 5 秒更新'
          : '$quality$routeDescription · Current route API response time, updated about every 5 seconds',
      child: Semantics(
        label: '$quality, $label$routeDescription',
        child: ExcludeSemantics(
          child: Container(
            constraints:
                const BoxConstraints(minHeight: ConnectionBadgeStyle.height),
            padding: const EdgeInsets.symmetric(
                horizontal: ConnectionBadgeStyle.horizontalInset,
                vertical: AppTokens.s2),
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.backgroundTop, palette.backgroundBottom]),
                borderRadius: BorderRadius.circular(AppTokens.rPill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ConnectionSignalIcon(palette: palette, offline: failed),
              const SizedBox(width: ConnectionBadgeStyle.iconGap),
              Flexible(
                  child: Transform.translate(
                      offset: const Offset(0, ConnectionBadgeStyle.textOffsetY),
                      child: Text.rich(
                          measured == null
                              ? TextSpan(text: label)
                              : TextSpan(children: [
                                  TextSpan(text: '$measured '),
                                  const TextSpan(
                                      text: 'ms',
                                      style: TextStyle(
                                          fontSize:
                                              ConnectionBadgeStyle.unitSize)),
                                  TextSpan(text: suffix),
                                ]),
                          key: textKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                              fontSize: ConnectionBadgeStyle.labelSize,
                              height: 1.2,
                              letterSpacing: 0,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: palette.text,
                              fontWeight: FontWeight.w700)))),
            ]),
          ),
        ),
      ),
    );
  }
}
