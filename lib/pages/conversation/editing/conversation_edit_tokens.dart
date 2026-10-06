import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Reference geometry for the conversation editing controls in 99chat.
class ConversationEditTokens {
  ConversationEditTokens._();

  static const double actionBarHeight = AppTokens.listItemHeight;
  static const double dividerWidth = .6;
  static const double selectionSize = AppTokens.s7;
  static const double selectionBorderWidth = 1.8;
  static const double checkSize = AppTokens.s5;
  static const double disabledOpacity = .38;
  static const Color delete = Color(0xFFEF3B36);
  static const Color dividerLight = Color(0xFFEAEAEA);

  static Color actionBarBackground({required bool dark}) =>
      dark ? AppTokens.backgroundDark : AppTokens.surfaceLight;

  static Color divider({required bool dark}) =>
      dark ? AppTokens.borderDark : dividerLight;
}
