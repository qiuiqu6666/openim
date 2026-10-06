import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// ContactCardUserPickerPage, ContactStyleSearchBar and DirectoryListStyle.
abstract final class ContactCardPickerTokens {
  static const avatarSize = 44.0;
  static const avatarTextGap = 12.0;
  static const horizontalPadding = 16.0;
  static const verticalPadding = 8.0;
  static const minimumRowHeight = 64.0;
  static const titleSize = 16.0;
  static const subtitleSize = 13.0;
  static const lineHeight = 1.25;
  static const textGap = 4.0;
  static const dividerThickness = .6;
  static const sectionSize = 12.0;
  static const indexSize = 11.0;
  static const indexOpacity = .8;
  static const minimumSectionHeight = 32.0;
  static const sectionVerticalPadding = 12.0;
  static const searchPadding = EdgeInsets.fromLTRB(16, 8, 16, 12);
  static const searchHorizontalPadding = 10.0;
  static const searchMinHeight = 44.0;
  static const searchSize = 15.0;
  static const searchLineHeight = 1.2;
  static const searchVerticalPadding = 20.0;
  static const searchRadius = 10.0;
  static const searchIconSize = 18.0;
  static const cancelGap = 10.0;
  static const cancelSize = 16.0;
  static const headingSize = 17.0;
  static const emptySize = 14.0;
  static const starSize = 18.0;
  static const starGap = 8.0;
  static const starColor = Color(0xFFF4B400);
  static const onlineDotSize = 12.0;
  static const onlineDotOffset = -1.5;
  static const onlineDotBorder = 2.0;
  static const onlineColor = Color(0xFF4CAF50);
  static const presenceSkeletonWidth = 64.0;
  static const presenceSkeletonHeight = 10.0;
  static const presenceSkeletonRadius = 4.0;
  static const presenceSkeletonOpacity = .22;
  static const indexBarWidth = 24.0;
  static const indexItemHeight = 16.0;
  static const indexRightMargin = 2.0;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBackground(BuildContext context) =>
      isDark(context) ? AppTokens.backgroundDark : AppTokens.surfaceLight;

  static Color rowBackground(BuildContext context) =>
      AppTokens.surface(dark: isDark(context));

  static Color searchBackground(BuildContext context) =>
      isDark(context) ? AppTokens.surfaceDark : AppTokens.surfaceAltLight;

  static Color primary(BuildContext context) =>
      AppTokens.textPrimary(dark: isDark(context));

  static Color secondary(BuildContext context) =>
      AppTokens.textSecondary(dark: isDark(context));

  static Color divider(BuildContext context) =>
      isDark(context) ? const Color(0x14FFFFFF) : const Color(0x0F000000);

  static double rowHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final textHeight = scaler.scale(titleSize) * lineHeight +
        scaler.scale(subtitleSize) * lineHeight +
        textGap;
    return math.max(
        minimumRowHeight,
        math.max(avatarSize, textHeight) +
            verticalPadding * 2 +
            dividerThickness);
  }

  static double sectionHeight(BuildContext context) => math.max(
      minimumSectionHeight,
      MediaQuery.textScalerOf(context).scale(sectionSize) * lineHeight +
          sectionVerticalPadding);

  static double searchHeight(BuildContext context) => math.max(
      searchMinHeight,
      MediaQuery.textScalerOf(context).scale(searchSize) * searchLineHeight +
          searchVerticalPadding);

  static double indexHeight(BuildContext context) => math.max(indexItemHeight,
      MediaQuery.textScalerOf(context).scale(indexSize) * lineHeight + 2);

  static TextStyle titleStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontSize: titleSize,
        fontWeight: FontWeight.w500,
        height: lineHeight,
        color: primary(context),
      );

  static TextStyle subtitleStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: subtitleSize,
        fontWeight: FontWeight.w400,
        height: lineHeight,
        color: secondary(context),
      );

  static TextStyle searchStyle(BuildContext context, {bool hint = false}) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: searchSize,
        height: searchLineHeight,
        color: hint ? secondary(context) : primary(context),
      );

  static TextStyle headingStyle(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
        fontSize: headingSize,
        fontWeight: FontWeight.w600,
        color: primary(context),
      );

  static TextStyle secondaryStyle(BuildContext context,
          {required double size}) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: size,
        height: lineHeight,
        color: secondary(context),
      );

  static TextStyle cancelStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: cancelSize,
        color: primary(context),
      );
}
