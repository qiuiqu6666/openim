import 'package:flutter/material.dart';

/// Exact visual measurements from 99chat chat_background_page.dart.
abstract final class ChatBackgroundReferenceTokens {
  static const scopeDark = Color(0xFF2A2D33);
  static const scopeLight = Color(0xFFEDEFF2);
  static const bannerDark = Color(0xFF23262D);
  static const bannerLight = Color(0xFFF0F4FA);
  static const bannerBorderLight = Color(0xFFD8E2F0);
  static const previewDark = Color(0xFF111111);
  static const previewLight = Color(0xFFF3F5F8);
  static const bubbleSelf = Color(0xFF2D8CFF);
  static const bubblePeerDark = Color(0xFF23262B);
  static const pagePadding = EdgeInsets.fromLTRB(12, 12, 12, 24);
  static const sectionMargin = EdgeInsets.fromLTRB(16, 12, 16, 0);
  static const bannerPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);
  static const colorGridPadding = EdgeInsets.fromLTRB(16, 10, 16, 18);
  static const imageGridPadding = EdgeInsets.fromLTRB(16, 12, 16, 18);
  static const headerPadding = EdgeInsets.fromLTRB(16, 14, 16, 10);
  static const desktopPreviewPadding = EdgeInsets.fromLTRB(20, 20, 20, 24);
  static const bubblePadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  static const badgePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  static const tileRadius = 10.0;
  static const scopeRadius = 18.0;
  static const scopeHeight = 36.0;
  static const bubbleWidth = 180.0;
  static const previewHeight = 168.0;
  static const hairline = 0.6;
  static const imageAspectRatio = 1.05;
  static const bannerLineHeight = 1.35;
}
