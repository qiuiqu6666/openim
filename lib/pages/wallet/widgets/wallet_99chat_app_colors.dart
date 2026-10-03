import 'package:flutter/material.dart';

import 'wallet_99chat_tokens.dart';

class AppColors {
  static const Color lightBackground = AppTokens.backgroundLight;
  static const Color lightCard = AppTokens.surfaceLight;
  static const Color lightText = AppTokens.textPrimaryLight;
  static const Color lightSubText = AppTokens.textSecondaryLight;
  static const Color lightLine = AppTokens.borderLight;
  static const Color lightShadow = AppTokens.shadowLight;

  static const Color darkBackground = AppTokens.backgroundDark;
  static const Color darkCard = AppTokens.surfaceDark;
  static const Color darkText = AppTokens.textPrimaryDark;
  static const Color darkSubText = AppTokens.textSecondaryDark;
  static const Color darkLine = AppTokens.borderDark;
  static const Color darkShadow = AppTokens.shadowDark;

  static const Color primaryBlue = AppTokens.accent;
  static const Color primaryRed = AppTokens.walletDanger;
  static const Color success = AppTokens.success;
  static const Color warning = AppTokens.warning;

  static Color background({required bool dark}) =>
      AppTokens.appBackground(dark);
  static Color card({required bool dark}) => AppTokens.appSurface(dark);
  static Color surfaceAlt({required bool dark}) =>
      AppTokens.appSurfaceAlt(dark);
  static Color text({required bool dark}) => AppTokens.appTextPrimary(dark);
  static Color subText({required bool dark}) =>
      AppTokens.appTextSecondary(dark);
  static Color line({required bool dark}) => AppTokens.appBorder(dark);
  static Color shadow({required bool dark}) => AppTokens.appShadow(dark);
}
