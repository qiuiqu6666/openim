import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Geometry from 99chat's conversation search and directory result rows.
abstract final class ChatHistorySearchTokens {
  static const horizontalPadding = 16.0;
  static const searchTopPadding = 8.0;
  static const searchBottomPadding = 12.0;
  static const searchMinHeight = 44.0;
  static const searchFontSize = 15.0;
  static const searchRadius = 10.0;
  static const searchIconSize = 18.0;
  static const searchLineHeight = 1.2;
  static const searchVerticalPadding = 10.0;
  static const searchIconMinWidth = 34.0;
  static const searchIconMinHeight = 40.0;
  static const searchSelectionOpacity = .25;
  static const cancelGap = 10.0;
  static const cancelFontSize = 16.0;
  static const shortcutTopPadding = 28.0;
  static const shortcutBottomPadding = 12.0;
  static const shortcutHeadingFontSize = 14.0;
  static const shortcutHeadingGap = 24.0;
  static const shortcutSize = 56.0;
  static const shortcutBackgroundOpacity = .12;
  static const shortcutIconSize = 28.0;
  static const shortcutLabelGap = 8.0;
  static const shortcutLabelFontSize = 14.0;
  static const shortcutSpacing = 40.0;
  static const shortcutRunSpacing = 20.0;
  static const rowMinHeight = 64.0;
  static const desktopRowMinHeight = 68.0;
  static const avatarSize = 44.0;
  static const desktopAvatarSize = 48.0;
  static const rowVerticalPadding = 8.0;
  static const avatarTextGap = 12.0;
  static const titleFontSize = 16.0;
  static const titleHeight = 1.25;
  static const timeFontSize = 12.0;
  static const timeMaxWidthRatio = .4;
  static const previewFontSize = 13.0;
  static const previewHeight = 1.35;
  static const textGap = 4.0;
  static const dividerThickness = .6;
  static const moreDividerThickness = .5;
  static const debounce = Duration(milliseconds: 500);
  static const loaderSize = 28.0;
  static const loaderStrokeWidth = 2.5;
  static const emptyImageWidth = 160.0;
  static const emptyVerticalPadding = 40.0;
  static const emptyHorizontalPadding = 32.0;
  static const emptyTextHeight = 1.4;

  static Color pageBackground({required bool dark}) =>
      dark ? AppTokens.backgroundDark : AppTokens.surfaceLight;
  static Color searchFill({required bool dark}) =>
      dark ? AppTokens.surfaceDark : AppTokens.surfaceAltLight;

  static double rowHeight(BuildContext context, {required bool desktop}) {
    final scaler = MediaQuery.textScalerOf(context);
    final textHeight = scaler.scale(titleFontSize) * titleHeight +
        scaler.scale(previewFontSize) * titleHeight +
        textGap;
    return math.max(
      desktop ? desktopRowMinHeight : rowMinHeight,
      math.max(desktop ? desktopAvatarSize : avatarSize, textHeight) +
          rowVerticalPadding * 2 +
          dividerThickness,
    );
  }

  static Color divider({required bool dark}) =>
      dark ? const Color(0x14FFFFFF) : const Color(0x0F000000);
}
