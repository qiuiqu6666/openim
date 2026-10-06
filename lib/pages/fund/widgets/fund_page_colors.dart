// Adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
// Source: lib/src/pages/wallet/widgets/wallet_page_colors.dart.
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// The reference wallet palette resolved through OpenIM's shared theme.
class FundPageColors {
  FundPageColors.of(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark;

  final bool dark;
  Color get bg => AppTokens.background(dark: dark);
  Color get card => AppTokens.surface(dark: dark);
  Color get text => AppTokens.textPrimary(dark: dark);
  Color get subText => AppTokens.textSecondary(dark: dark);
  Color get line => AppTokens.border(dark: dark);
  Color get shadow => dark ? const Color(0x2D000000) : const Color(0x080B1220);
  Color get red => AppTokens.walletDanger;
  Color get blue => AppTokens.accent;
  Color get inputCursor => AppTokens.accent;
  Color get inputHint => subText;
  Color get inputFill => AppTokens.surfaceAlt(dark: dark);
  Color get avatarPlaceholder =>
      dark ? AppTokens.borderDark : const Color(0xFFD7EBFF);
  Color get avatarIcon =>
      dark ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563);
  Color get filterActiveBg =>
      dark ? blue.withValues(alpha: .28) : const Color(0xFFEAF4FF);
  Color get filterActiveText => dark ? Colors.white : blue;
  Color get filterActiveBorder => dark ? blue : blue.withValues(alpha: .35);
  Color get filterInactiveBg => inputFill;
  Color get filterInactiveText => text;
  Color get tagBg => dark ? const Color(0xFF332716) : const Color(0xFFFFF7E8);
  Color get tagBorder => AppTokens.warning.withValues(alpha: dark ? .45 : .25);
  Color get tagTextColor => dark ? const Color(0xFFE8C46A) : AppTokens.warning;
  Color get warningBg => tagBg;
  Color get warningText => tagTextColor;
  Color get warningIconBg => dark ? AppTokens.warning : const Color(0xFFF2C230);
  Color get surfaceAlt => inputFill;
  Color get disabledButton =>
      dark ? const Color(0xFF3A3D45) : const Color(0xFFD1D5DB);
}
