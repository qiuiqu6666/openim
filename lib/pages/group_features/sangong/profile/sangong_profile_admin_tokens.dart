import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Geometry from 99chat d7c3c65 user_profile_game_admin_panel.dart.
class SangongProfileAdminTokens {
  SangongProfileAdminTokens._();

  static const double captionSize = 15;
  static const double inputSize = 17;
  static const double hintSize = 16;
  static const double captionHeight = 20;
  static const double summaryHeight = 40;
  static const double sectionRadius = 12;
  static const double inputRadius = 6;
  static const double sectionBorderWidth = .5;
  static const EdgeInsets sectionInset = EdgeInsets.fromLTRB(12, 10, 12, 10);
  static const EdgeInsets inputInset =
      EdgeInsets.symmetric(horizontal: 10, vertical: 8);
  static const EdgeInsets actionInset =
      EdgeInsets.symmetric(horizontal: 10, vertical: 8);
  static const Duration transition = Duration(milliseconds: 180);
  static const double sideWidth = 360;
  static const double sideHeaderHeight = 56;
  static const BoxShadow embeddedShadow =
      BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2));

  static Color inputFill(bool dark) =>
      dark ? AppTokens.borderDark : const Color(0xFFF3F4F6);
  static EdgeInsets sectionMargin(bool embedded) =>
      EdgeInsets.fromLTRB(embedded ? 12 : 16, 0, embedded ? 12 : 16, 8);
}
