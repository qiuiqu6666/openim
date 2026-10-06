import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Mobile details values from 99chat's user_profile.dart.
abstract final class UserProfileTokens {
  static const avatarSize = 78.0;
  static const avatarGap = 14.0;
  static const nameSize = 22.0;
  static const genderSize = 18.0;
  static const accountRadius = 18.0;
  static const copyIconSize = 15.0;
  static const copyTouchTarget = 48.0;
  // Keep the reference's blue/white primary action readable in both themes.
  static const primaryAction = Color(0xFF0875E1);
  static const actionIconSize = 25.0;
  static const actionGap = 10.0;
  static const identityGap = 6.0;
  static const signatureLineHeight = 1.3;
  static const signatureMaxLines = 2;
  static const navigationIconSize = 22.0;
  static const menuIconSize = 28.0;
  static const rowFontSize = 16.0;
  static const headerPadding = EdgeInsets.fromLTRB(20, 22, 16, 22);
  static const actionPadding = EdgeInsets.fromLTRB(12, 4, 12, 14);
  static const actionContentPadding =
      EdgeInsets.symmetric(horizontal: 6, vertical: 16);
  static const accountPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 4);
  static const cardMargin = EdgeInsets.fromLTRB(12, 0, 12, 12);
  static const femaleColor = Color(0xFFFF6B9D);
  static const maleColor = Color(0xFF4DA3FF);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color background(BuildContext context) =>
      isDark(context) ? const Color(0xFF111318) : AppTokens.backgroundLight;
  static Color card(BuildContext context) =>
      isDark(context) ? const Color(0xFF1D2027) : AppTokens.surfaceLight;
  static Color divider(BuildContext context) =>
      isDark(context) ? const Color(0xFF343842) : const Color(0xFFE9ECF1);
  static Color text(BuildContext context) =>
      AppTokens.textPrimary(dark: isDark(context));
  static Color muted(BuildContext context) =>
      AppTokens.textSecondary(dark: isDark(context));
  static Color account(BuildContext context) =>
      AppTokens.surfaceAlt(dark: isDark(context));
}
