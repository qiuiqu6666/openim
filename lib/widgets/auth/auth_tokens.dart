import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Geometry shared by the login, registration and recovery flows.
abstract final class AuthTokens {
  static const maxWidth = 440.0;
  static const controlHeight = 52.0;
  static const touchTarget = 48.0;
  static const brandSize = 56.0;
  static const titleSize = 28.0;
  static const gutter = AppTokens.s7;
  static const fieldGap = AppTokens.s6;
  static const sectionGap = AppTokens.s8;
  static const radius = AppTokens.rLg;
  static const welcomeBrandSize = 64.0;
  static const welcomeHeaderGap = 28.0;
  static const welcomeFieldGap = AppTokens.s5;
  static const welcomeButtonSize = 20.0;
  static const welcomeInputIconSize = 18.0;
  static const welcomeInputRadius = AppTokens.rMd;
  static const welcomeInputDividerHeight = AppTokens.s6;

  static Color link(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.primary
          : const Color(0xFF0072E5);

  static Color welcomeSurface(BuildContext context) => Color.alphaBlend(
      Theme.of(context).colorScheme.onSurface.withValues(alpha: .035),
      background(context));

  static Color welcomeInputFill(BuildContext context) => Color.alphaBlend(
      Theme.of(context).colorScheme.onSurface.withValues(alpha: .025),
      background(context));

  static Color welcomeInputBorder(BuildContext context) =>
      AppTokens.border(dark: Theme.of(context).brightness == Brightness.dark);

  static TextStyle welcomeInputText(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
            fontSize: AppTokens.captionFontSize,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurface,
          );

  static TextStyle welcomeInputHint(BuildContext context) =>
      welcomeInputText(context).copyWith(
        color: Color.lerp(
          AppTokens.textSecondary(
              dark: Theme.of(context).brightness == Brightness.dark),
          Theme.of(context).colorScheme.onSurfaceVariant,
          .35,
        ),
      );

  static Gradient welcomeGradient(BuildContext context) => LinearGradient(
        colors: Theme.of(context).brightness == Brightness.dark
            ? [Theme.of(context).colorScheme.primary, AppTokens.accent]
            : const [Color(0xFF4898F0), Color(0xFF2684FF)],
      );

  static Color background(BuildContext context) =>
      AppTokens.surface(dark: Theme.of(context).brightness == Brightness.dark);

  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            height: 1.3,
          );

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: AppTokens.captionFontSize,
            height: 1.6,
          );

  static TextStyle action(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
            fontSize: AppTokens.listTitleFontSize,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onPrimary,
          );
}
