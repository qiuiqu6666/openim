import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Values verified against reference-99chat channel screens (2026-10-22).
abstract final class ChannelTokens {
  static const notificationBarHeight = 54.0;
  static const backgroundLight = Color(0xFFF4F7FD);
  static const blue = Color(0xFF2387EE);
  static const blueDark = Color(0xFF69B4FF);
  static const avatar = 70.0;
  static const sheetFraction = .9;
  static const cardRadius = 14.0;
  static const formRadius = 10.0;
  static const sheetRadius = 28.0;
  static const pageInset = 16.0;
  static const formBlue = Color(0xFF2388F0);
  static const hint = Color(0xFFB3B7BF);
  static const secondary = Color(0xFF818A99);
  static const disabled = Color(0xFFDDE0E6);
  static const avatarFill = Color(0xFFE9F4FF);
  static const linkFill = Color(0xFFF5F7FC);
  static const menuBorder = Color(0xFFE8EDF5);
  static const menuShadow = Color(0x330B2547);
  static const menuClearFill = Color(0xFFEEF5FF);
  static const menuDangerFill = Color(0xFFFFF0EE);
  static const menuDanger = Color(0xFFE94B43);
  static const ink = Color(0xFF172033);
  static Color surface(BuildContext c) =>
      AppTokens.surface(dark: Theme.of(c).brightness == Brightness.dark);
  static Color background(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppTokens.backgroundDark
          : backgroundLight;
  static Color muted(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppTokens.textSecondary(dark: true)
          : MediaQuery.highContrastOf(c)
              ? const Color(0xFF596575)
              : secondary;
  static Color button(BuildContext c) =>
      MediaQuery.highContrastOf(c) ? const Color(0xFF0067CE) : blue;
  static Color action(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? blueDark : button(c);
}
