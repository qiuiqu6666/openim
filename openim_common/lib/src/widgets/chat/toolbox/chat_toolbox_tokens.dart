import 'package:flutter/material.dart';

import '../../../res/app_tokens.dart';

/// 99chat MorePanelStyles and the mobile host's actual 248dp panel constraint.
abstract final class ChatToolboxTokens {
  static const panelHeight = 248.0;
  static const panelAnimationDuration = Duration(milliseconds: 200);
  static const itemsPerPage = 8;
  static const columns = 4;
  static const itemWidth = 64.0;
  static const itemHeight = 94.0;
  static const iconSlotSize = 64.0;
  static const iconSize = 56.0;
  // Reference artwork includes canvas padding; native glyphs do not.
  static const symbolSize = 26.0;
  static const iconBottomMargin = 4.0;
  static const labelGap = 4.0;
  static const labelSize = 12.0;
  static const rowGap = 20.0;
  static const panelPadding = 20.0;
  static const spacingCalculationSide = 23.0;
  static const radius = AppTokens.rLg;
  static const dividerWidth = 1.0;
  static const indicatorSize = 6.0;
  static const indicatorGap = 3.0;
  static const indicatorBottom = 8.0;
  static const indicatorHeight = indicatorSize + indicatorBottom;
  static const inactiveIndicatorOpacity = .45;
  static const disabledOpacity = .38;
  static const iconLight = Color(0xFF4B5563);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color panelBackground(BuildContext context) =>
      isDark(context) ? AppTokens.backgroundDark : AppTokens.surfaceLight;

  static Color tileBackground(BuildContext context) =>
      isDark(context) ? AppTokens.surfaceDark : AppTokens.surfaceAltLight;

  static Color iconColor(BuildContext context) =>
      isDark(context) ? AppTokens.textPrimaryDark : iconLight;

  static Color labelColor(BuildContext context) =>
      AppTokens.textSecondary(dark: isDark(context));

  static Color dividerColor(BuildContext context) =>
      ChatComposerTokens.divider(dark: isDark(context));

  static TextStyle labelStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: labelSize,
        fontWeight: FontWeight.w400,
        height: 1.2,
        letterSpacing: 0,
        color: labelColor(context),
      );
}
