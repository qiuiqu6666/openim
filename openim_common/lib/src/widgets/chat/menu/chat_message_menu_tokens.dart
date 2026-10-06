import 'package:flutter/material.dart';

import '../../../res/app_tokens.dart';

/// Shared geometry and colors for the 99chat message action menu.
class ChatMessageMenuTokens {
  ChatMessageMenuTokens._();

  static const Color background = Color(0xFF4C4C4C);
  static const Color foreground = AppTokens.onAccent;
  static const Color destructive = Color(0xFFFF747C);

  static const int columns = 5;
  static const int itemsPerPage = 10;
  static const double panelWidth = 300;
  static const double cellWidth = 56;
  static const double cellHeight = 52;
  static const double horizontalPadding = 10;
  static const double verticalPadding = 8;
  static const double radius = 12;
  static const double iconSize = 22;
  static const double labelSize = 10;
  static const double labelHeight = 1.1;
  static const double iconGap = 4;
  static const double gap = 8;
  static const double edgePadding = 12;
  static const double arrowWidth = 16;
  static const double arrowHeight = 8;
  static const Duration animationDuration = Duration(milliseconds: 220);
  static const double scaleBegin = .96;
  static const double scrimOpacity = .32;
}
