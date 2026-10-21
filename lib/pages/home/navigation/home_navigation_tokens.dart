import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Home-only glass styling; shared headers keep their existing material.
abstract final class HomeNavigationTokens {
  // Give the icon + label capsule breathing room above the system safe area.
  static const height = 64.0;
  static const inset = NavigationGlassTokens.inset;
  static const radius = height / 2;
  static const selectionInset = AppTokens.s2;
  static const labelSize = 12.0;
  static const iconSize = 24.0;
  static const badgeTop = -5.0;
  static const badgeStart = 16.0;

  static double opacity(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? .24 : .30;

  static Color edge(BuildContext context) =>
      NavigationGlassTokens.backgroundColor(context).withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .32 : .88);

  static Color selection(BuildContext context) => Color.lerp(
        AppTokens.accent,
        NavigationGlassTokens.backgroundColor(context),
        Theme.of(context).brightness == Brightness.dark ? .86 : .94,
      )!
          .withValues(alpha: .38);

  static BoxShadow shadow(BuildContext context) => BoxShadow(
      color: Theme.of(context).shadowColor.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .26 : .10),
      blurRadius: AppTokens.s5,
      offset: const Offset(0, AppTokens.s2));
}
