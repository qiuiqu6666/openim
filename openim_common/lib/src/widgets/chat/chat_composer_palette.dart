import 'package:flutter/material.dart';
import '../../res/app_tokens.dart';
import '../../res/typography/platform_text_fonts.dart';

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
  return TextStyle(
    inherit: false,
    fontFamily: PlatformTextFonts.familyOf(context),
    fontFamilyFallback: PlatformTextFonts.fallbackOf(context),
    fontSize: ChatComposerTokens.fontSize,
    height: ChatComposerTokens.lineHeight,
    fontWeight: FontWeight.w400,
    textBaseline: TextBaseline.alphabetic,
    color: hint ? chatComposerHint(context) : chatComposerForeground(context),
  );
}
