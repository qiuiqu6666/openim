import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Metrics shared by 99chat's new friends and group notice lists.
abstract final class RequestHistoryStyle {
  static const avatar = 44.0;
  static const groupAvatar = 48.0;
  static const groupGap = 14.0;
  static const titleSize = 16.0;
  static const subtitleSize = 13.0;
  static const metadataSize = 12.0;
  static const lineHeight = 1.25;
  static const dividerWidth = .6;
  static const titleGap = 6.0;
  static const stackWidth = 320.0;
  static const stackTextSize = 22.0;
  static const badgeHeight = 30.0;
  static const badgeRadius = 15.0;
  static const badgeIcon = 15.0;
  static const badgeHorizontal = 10.0;
  static const badgeVertical = 5.0;
  static const actionHeight = 34.0;
  static const actionWidth = 64.0;
  static const headingSize = 18.0;
  static const backIcon = 22.0;
  static const sectionVertical = 10.0;

  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color surface(BuildContext context) =>
      AppTokens.surface(dark: dark(context));
  static Color background(BuildContext context) =>
      AppTokens.background(dark: dark(context));
  static Color secondary(BuildContext context) =>
      AppTokens.textSecondary(dark: dark(context));
  static Color divider(BuildContext context) =>
      (dark(context) ? AppTokens.onAccent : Colors.black)
          .withValues(alpha: dark(context) ? .08 : .06);
  static TextStyle title(BuildContext context) => TextStyle(
      color: AppTokens.textPrimary(dark: dark(context)),
      fontSize: titleSize,
      height: lineHeight,
      fontWeight: FontWeight.w500);
  static TextStyle subtitle(BuildContext context) => TextStyle(
      color: secondary(context), fontSize: subtitleSize, height: 1.35);
  static TextStyle metadata(BuildContext context) => TextStyle(
      color: secondary(context), fontSize: metadataSize, height: lineHeight);
}
