import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
export 'ai_metrics.dart';

/// Light values from the real 99chat AI assistant; dark values use host tokens.
class AiPalette {
  const AiPalette._();
  static const Color header = Color(0xFFF8FAFF);
  static const Color canvas = Color(0xFFF1F5FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color userBubble = Color(0xFF2688F5);
  static const Color input = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF182230);
  static const Color subText = Color(0xFF7C899D);
  static const Color border = Color(0xFFE3E9F2);
  static const Color accent = Color(0xFF4B7BFF);
  static const Color backdropBottomLight = Color(0xFFE8EEF8);
  static const Color searchHit = Color(0xFFFFEB3B);
  static const Color guideStart = Color(0xFF6EB0FF);
  static const Color guideEnd = Color(0xFF3D7DFF);
  static const Color inputShadow = Color(0x140B1220);
  static const Color codeDark = AppTokens.surfaceAltDark;
  static const Color codeLight = Color(0xFF1F2937);
  static const Color codeText = AppTokens.textPrimaryDark;
  static const Color onAccent = AppTokens.onAccent;
  static const Color mask = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);
  static const Color pdf = Color(0xFFE60022);
  static const Color word = Color(0xFF2B579A);
  static const Color excel = Color(0xFF217346);
  static const Color ppt = Color(0xFFD24726);
  static const Color image = Color(0xFF7C3AED);
  static const Color video = Color(0xFF0EA5E9);
  static const Color audio = Color(0xFFDB2777);
  static const Color textFile = Color(0xFF4B5563);
  static const Color archive = Color(0xFFCA8A04);
  static const Color unknownFile = Color(0xFF6B7280);

  static Color headerBg(bool dark) => dark ? AppTokens.surfaceDark : header;
  static Color canvasBg(bool dark) => dark ? AppTokens.backgroundDark : canvas;
  static Color cardBg(bool dark) => dark ? AppTokens.surfaceDark : card;
  static Color inputBg(bool dark) => dark ? AppTokens.surfaceAltDark : input;
  static Color primary(bool dark) => dark ? AppTokens.textPrimaryDark : text;
  static Color secondary(bool dark) =>
      dark ? AppTokens.textSecondaryDark : subText;
  static Color line(bool dark) => dark ? AppTokens.borderDark : border;
  static Color brand(bool dark) => dark ? AppTokens.accent : accent;
  static Color bubble(bool dark) => dark ? AppTokens.accent : userBubble;
}
