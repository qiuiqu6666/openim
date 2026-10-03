import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Wallet-local mirror of 99chat `lib/src/ui/app_tokens.dart` at
/// d7c3c655b20dd06458d1882b114e68c1c24133e3.
///
/// Keeping these tokens local prevents Wallet parity work from changing the
/// OpenIM-wide theme used by Settings, Chat, Contacts, and Mine.
class AppTokens {
  AppTokens._();

  static const Color brand500 = Color(0xFF1E90FF);
  static const Color brand600 = Color(0xFF1E90FF);
  static const Color brand700 = Color(0xFF1E90FF);
  static const Color brand400 = Color(0xFF1E90FF);
  static const Color brand300 = Color(0xFF1E90FF);
  static const Color brand50 = Color(0xFFEAF4FF);
  static const Color brand100 = Color(0xFFD7EBFF);

  static const Color ink900 = Color(0xFF0B1220);
  static const Color ink800 = Color(0xFF111827);
  static const Color ink700 = Color(0xFF1F2937);
  static const Color ink600 = Color(0xFF374151);
  static const Color ink500 = Color(0xFF4B5563);
  static const Color ink400 = Color(0xFF6B7280);
  static const Color ink300 = Color(0xFF9CA3AF);
  static const Color ink200 = Color(0xFFD1D5DB);
  static const Color ink150 = Color(0xFFE6E6E9);
  static const Color ink100 = Color(0xFFE5E7EB);
  static const Color ink50 = Color(0xFFF3F4F6);
  static const Color ink25 = Color(0xFFF9FAFB);

  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFFAFBFC);
  static const Color divider = Color(0xFFEEF0F4);
  static const Color fieldFill = Color(0xFFF1F2F4);

  static const Color backgroundLight = Color(0xFFF5F6F8);
  static const Color surfaceLight = Colors.white;
  static const Color surfaceAltLight = Color(0xFFF1F3F5);
  static const Color textPrimaryLight = Color(0xFF1C1C1E);
  static const Color textSecondaryLight = Color(0xFF7B8491);
  static const Color borderLight = Color(0xFFE6E8EC);
  static const Color shadowLight = Color(0x080B1220);

  static const Color backgroundDark = Color(0xFF101114);
  static const Color surfaceDark = Color(0xFF1B1D22);
  static const Color surfaceAltDark = Color(0xFF23262D);
  static const Color textPrimaryDark = Color(0xFFF4F4F4);
  static const Color textSecondaryDark = Color(0xFF9A9CA3);
  static const Color borderDark = Color(0xFF2A2D33);
  static const Color shadowDark = Color(0x2D000000);

  static const Color accent = brand500;
  static const Color accentSoft = brand50;
  static const Color danger = Color(0xFFDC2626);
  static const Color walletDanger = Color(0xFFE60022);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSurfaceLight = Color(0xFFFFF7E8);
  static const Color warningSurfaceDark = Color(0xFF332716);

  static Color appBackground(bool dark) =>
      dark ? backgroundDark : backgroundLight;
  static Color appSurface(bool dark) => dark ? surfaceDark : surfaceLight;
  static Color appSurfaceAlt(bool dark) =>
      dark ? surfaceAltDark : surfaceAltLight;
  static Color appTextPrimary(bool dark) =>
      dark ? textPrimaryDark : textPrimaryLight;
  static Color appTextSecondary(bool dark) =>
      dark ? textSecondaryDark : textSecondaryLight;
  static Color appBorder(bool dark) => dark ? borderDark : borderLight;
  static Color appShadow(bool dark) => dark ? shadowDark : shadowLight;

  static const double s2 = 4;
  static const double s3 = 8;
  static const double s4 = 12;
  static const double s5 = 16;
  static const double s6 = 20;
  static const double s7 = 24;
  static const double s8 = 32;
  static const double s9 = 40;
  static const double s10 = 56;

  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 14;
  static const double rCard = 18;
  static const double rXl = 20;
  static const double rPill = 999;

  static const double buttonHeight = 48;
  static const double listItemHeight = 56;

  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: const Color(0xFF0B1220).withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: const Color(0xFF0B1220).withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: const Color(0xFF0B1220).withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get shadowBrand => const [];

  static String? get fontFamily => kIsWeb ? 'NotoSansSC' : null;

  static String? get desktopUiFontFamily {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'Microsoft YaHei UI';
      case TargetPlatform.macOS:
        return 'PingFang SC';
      case TargetPlatform.linux:
        return 'Noto Sans CJK SC';
      case TargetPlatform.iOS:
        return kIsWeb ? 'PingFang SC' : null;
      case TargetPlatform.android:
        return kIsWeb ? 'sans-serif' : null;
      default:
        return null;
    }
  }

  static String? fontFamilyOf(BuildContext context) =>
      desktopUiFontFamily ?? fontFamily;

  static List<String>? fontFamilyFallbackOf(BuildContext context) => null;
}
