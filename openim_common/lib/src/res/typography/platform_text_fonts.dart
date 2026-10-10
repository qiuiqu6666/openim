import 'package:flutter/material.dart';

/// Existing UI font preferences without replacing the platform's font fallback.
///
/// Mobile deliberately leaves both properties unset. Flutter can then resolve
/// complete Unicode runs with the device's native text and Emoji fonts. Desktop
/// keeps the established Chinese UI fonts; unhandled glyphs continue through
/// Flutter's system fallback after these optional preferences.
abstract final class PlatformTextFonts {
  static String? familyFor(TargetPlatform platform) => switch (platform) {
        TargetPlatform.windows => 'Microsoft YaHei UI',
        TargetPlatform.macOS => 'PingFang SC',
        TargetPlatform.linux => 'Noto Sans CJK SC',
        _ => null,
      };

  static List<String>? fallbackFor(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.windows => const ['Microsoft YaHei', 'Segoe UI'],
        TargetPlatform.macOS => const ['PingFang TC', 'Hiragino Sans GB'],
        TargetPlatform.linux => const [
            'Noto Sans CJK TC',
            'WenQuanYi Micro Hei'
          ],
        _ => null,
      };

  static String? familyOf(BuildContext context) =>
      familyFor(Theme.of(context).platform);

  static List<String>? fallbackOf(BuildContext context) =>
      fallbackFor(Theme.of(context).platform);
}
