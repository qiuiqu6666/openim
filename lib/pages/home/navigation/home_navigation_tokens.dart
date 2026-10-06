import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Home-only glass styling; shared headers keep their existing material.
abstract final class HomeNavigationTokens {
  static const height = kBottomNavigationBarHeight;
  static const inset = NavigationGlassTokens.inset;
  static const radius = NavigationGlassTokens.radius;
  static const selectionInset = AppTokens.s2;
  static const labelSize = 11.0;

  static double opacity(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? .40 : .44;

  static Color edge(BuildContext context) =>
      NavigationGlassTokens.backgroundColor(context).withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .32 : .88);

  static Color selection(BuildContext context) => Color.lerp(
        AppTokens.accent,
        NavigationGlassTokens.backgroundColor(context),
        Theme.of(context).brightness == Brightness.dark ? .86 : .94,
      )!
          .withValues(alpha: .78);

  static BoxShadow shadow(BuildContext context) => BoxShadow(
      color: Theme.of(context).shadowColor.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .26 : .10),
      blurRadius: AppTokens.s5,
      offset: const Offset(0, AppTokens.s2));
}
