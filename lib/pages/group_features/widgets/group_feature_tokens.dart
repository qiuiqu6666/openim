import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Theme-aware equivalents of the reference surfaces, without changing its geometry.
class GroupFeatureTokens {
  GroupFeatureTokens.of(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get surface => AppTokens.surface(dark: dark);
  Color get background => AppTokens.background(dark: dark);
  Color get surfaceAlt => AppTokens.surfaceAlt(dark: dark);
  Color get text => AppTokens.textPrimary(dark: dark);
  Color get secondary => AppTokens.textSecondary(dark: dark);
  Color get primary => AppTokens.accent;
  Color get divider => AppTokens.border(dark: dark);
  Color get error => AppTokens.paymentError(dark: dark);
  double get cardRadius => 12;
  double get inset => 16;
  TextStyle get pageText => TextStyle(fontSize: 15, color: text);
}
