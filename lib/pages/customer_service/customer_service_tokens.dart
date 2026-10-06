import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Geometry and colors shared by the native 99chat customer-service surface.
abstract final class CustomerServiceTokens {
  static const blue = Color(0xFF2B7FE0);
  static const lightBackground = Color(0xFFE8F1FB);
  static const foreground = AppTokens.onAccent;

  static const sheetHeightFactor = 0.8;
  static const sheetRadius = 16.0;
  static const sheetDuration = Duration(milliseconds: 260);
  static const scrimOpacity = 0.55;
  static const tapMinHeight = 44.0;
  static const chipMinHeight = 32.0;
  static const chipRadius = AppTokens.rSm;
  static const chipFontSize = 12.0;
  static const categoryColumnGap = 6.0;
  static const categoryRowGap = 8.0;
  static const categoryInactiveOpacity = 0.45;
  static const categoryPadding =
      EdgeInsets.symmetric(horizontal: 10, vertical: 10);
  static const categoryHitPadding = EdgeInsets.symmetric(vertical: 6);
  static const categoryChipPadding =
      EdgeInsets.symmetric(horizontal: 4, vertical: 6);
  static const cardRadius = AppTokens.rMd;
  static const faqRowMinHeight = 48.0;
  static const faqFontSize = 14.0;
  static const headerFontSize = 16.0;
  static const panelInset = AppTokens.s4;
  static const faqIconSize = 16.0;
  static const dividerWidth = 1.0;
  static const faqRowPadding =
      EdgeInsets.symmetric(horizontal: panelInset, vertical: 10);
  static const answerHeaderPadding = EdgeInsets.symmetric(vertical: 8);
  static const answerPadding = EdgeInsets.fromLTRB(16, 12, 16, 16);
  static const faqIconGap = 8.0;
  static const answerLinkGap = 12.0;
  static const chevronSize = 22.0;
  static const answerLineHeight = 1.5;
  static const headerHeight = 116.0;
  static const inputMinHeight = 64.0;
  static const messageMaxWidthFactor = 0.76;
  static const mediaWidth = 200.0;
  static const mediaHeight = 160.0;
  static const closeSize = 28.0;
  static const closeTapSize = 48.0;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color background(BuildContext context) =>
      isDark(context) ? AppTokens.background(dark: true) : lightBackground;
  static Color surface(BuildContext context) =>
      AppTokens.surface(dark: isDark(context));
  static Color text(BuildContext context) =>
      AppTokens.textPrimary(dark: isDark(context));
  static Color secondaryText(BuildContext context) =>
      AppTokens.textSecondary(dark: isDark(context));
  static Color border(BuildContext context) =>
      AppTokens.border(dark: isDark(context));
}
