import 'package:flutter/material.dart';

import '../../../res/app_tokens.dart';

/// Geometry and colors from 99chat's reply preview and quote card.
abstract final class ChatQuoteTokens {
  static const thumbnailSize = 40.0;
  static const thumbnailRadius = 4.0;
  static const titleSize = 13.0;
  static const summarySize = 12.0;
  static const lineHeight = 1.35;
  static const titleGap = 2.0;
  static const cardRadius = 5.0;
  static const cardVerticalPadding = 6.0;
  static const borderWidth = 3.0;
  static const closeIconSize = 18.0;

  static bool usesLightText(Color bubble) =>
      ThemeData.estimateBrightnessForColor(bubble) == Brightness.dark;
  static Color background(Color bubble) => usesLightText(bubble)
      ? AppTokens.onAccent.withValues(alpha: .22)
      : const Color(0x1F000000);
  static Color border(Color bubble) => usesLightText(bubble)
      ? AppTokens.onAccent.withValues(alpha: .55)
      : const Color(0x4D000000);
  static Color sender(Color bubble) =>
      usesLightText(bubble) ? AppTokens.onAccent : AppTokens.accent;
  static Color summary(Color bubble) => usesLightText(bubble)
      ? AppTokens.textPrimaryDark.withValues(alpha: .82)
      : AppTokens.ink600;
}
