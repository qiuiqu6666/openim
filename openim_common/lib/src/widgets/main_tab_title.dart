import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../res/app_tokens.dart';
import 'fading_arc_spinner.dart';

/// Main-tab title from 99chat home_page.dart, using OpenIM connection state.
class MainTabTitle extends StatelessWidget {
  const MainTabTitle(
      {super.key,
      required this.title,
      this.busy = false,
      this.busyLabel,
      this.failed = false,
      this.color,
      this.keyPrefix = 'main-tab-title'});
  final String title;
  final bool busy, failed;
  final String? busyLabel;
  final Color? color;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = color ?? AppTokens.textPrimary(dark: dark);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = (!kIsWeb &&
            const {
              TargetPlatform.windows,
              TargetPlatform.macOS,
              TargetPlatform.linux
            }.contains(defaultTargetPlatform)) ||
        width > 900 ||
        (kIsWeb && width > MediaQuery.sizeOf(context).height * 1.1);
    final fontSize = desktop
        ? AppTokens.mainTabTitleDesktopFontSize
        : AppTokens.mainTabTitleFontSize;
    final label = busy
        ? busyLabel ??
            (Localizations.localeOf(context).languageCode == 'zh'
                ? '正在连接'
                : 'Connecting')
        : title;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s2),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(label,
                      key: ValueKey('$keyPrefix-text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: foreground,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          height: 1))),
              if (busy || failed) ...[
                const SizedBox(width: AppTokens.s3),
                if (busy)
                  FadingArcSpinner(
                      size: fontSize * .72,
                      color: AppTokens.accent,
                      strokeWidth: 2.2)
                else
                  Icon(Icons.error_outline_rounded,
                      size: fontSize * .72,
                      color: foreground.withValues(alpha: .72)),
              ],
            ]),
            if (!busy && !failed) ...[
              const SizedBox(height: AppTokens.mainTabIndicatorTitleGap),
              Transform.translate(
                  offset: const Offset(0, -2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        key: ValueKey('$keyPrefix-indicator-line'),
                        width: desktop
                            ? AppTokens.mainTabIndicatorDesktopWidth
                            : AppTokens.mainTabIndicatorWidth,
                        height: AppTokens.mainTabIndicatorHeight,
                        decoration: BoxDecoration(
                            color: AppTokens.accent,
                            borderRadius:
                                BorderRadius.circular(AppTokens.rPill))),
                    const SizedBox(width: AppTokens.mainTabIndicatorGap),
                    Container(
                        key: ValueKey('$keyPrefix-indicator-dot'),
                        width: AppTokens.mainTabIndicatorDotSize,
                        height: AppTokens.mainTabIndicatorDotSize,
                        decoration: BoxDecoration(
                            color: AppTokens.accent.withValues(alpha: .78),
                            shape: BoxShape.circle)),
                  ])),
            ],
          ]),
    );
  }
}
