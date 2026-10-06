import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../res/app_tokens.dart';

/// Colors from 99chat's production DefTheme, resolved with the active theme.
Color chatComposerSurface(BuildContext context) => ChatComposerTokens.surface(
    dark: Theme.of(context).brightness == Brightness.dark);

Color chatComposerInputFill(BuildContext context) =>
    ChatComposerTokens.inputFill(
        dark: Theme.of(context).brightness == Brightness.dark);

Color chatComposerDivider(BuildContext context) => ChatComposerTokens.divider(
    dark: Theme.of(context).brightness == Brightness.dark);

Color chatComposerForeground(BuildContext context) => AppTokens.textPrimary(
    dark: Theme.of(context).brightness == Brightness.dark);

Color chatComposerHint(BuildContext context) => AppTokens.textSecondary(
    dark: Theme.of(context).brightness == Brightness.dark);

/// 99chat's input typography does not inherit Material body/label spacing.
/// Mobile uses the system font; desktop uses the same CJK UI font fallbacks.
TextStyle chatComposerTextStyle(BuildContext context, {bool hint = false}) {
  final platform = Theme.of(context).platform;
  final fontFamily = kIsWeb
      ? 'NotoSansSC'
      : switch (platform) {
          TargetPlatform.windows => 'Microsoft YaHei UI',
          TargetPlatform.macOS => 'PingFang SC',
          TargetPlatform.linux => 'Noto Sans CJK SC',
          _ => null,
        };
  final fallback = switch (platform) {
    TargetPlatform.windows => const ['Microsoft YaHei', 'Segoe UI'],
    TargetPlatform.macOS => const ['PingFang TC', 'Hiragino Sans GB'],
    TargetPlatform.linux => const ['Noto Sans CJK TC', 'WenQuanYi Micro Hei'],
    _ => null,
  };
  return TextStyle(
    inherit: false,
    fontFamily: fontFamily,
    fontFamilyFallback: kIsWeb ? null : fallback,
    fontSize: ChatComposerTokens.fontSize,
    height: ChatComposerTokens.lineHeight,
    fontWeight: FontWeight.w400,
    textBaseline: TextBaseline.alphabetic,
    color: hint ? chatComposerHint(context) : chatComposerForeground(context),
  );
}
