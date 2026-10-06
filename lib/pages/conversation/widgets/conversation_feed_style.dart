import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Geometry and colors from 99chat's conversation_feed_ui.dart (d7c3c65).
class ConversationFeedStyle {
  ConversationFeedStyle._();

  static const lineHeight = 1.2;
  static const dividerHeight = .6;
  static const dividerLight = Color(0xFFEAEAEA);

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      _dark(context) ? AppTokens.backgroundDark : AppTokens.surfaceLight;

  static Color rowBackground(BuildContext context, {bool pinned = false}) =>
      pinned ? AppTokens.surfaceAlt(dark: _dark(context)) : background(context);

  static Color divider(BuildContext context) =>
      _dark(context) ? AppTokens.borderDark : dividerLight;

  static double rowHeight(BuildContext context) =>
      72 + ((MediaQuery.textScalerOf(context).scale(1) - 1) * 16).clamp(0, 8);
}
