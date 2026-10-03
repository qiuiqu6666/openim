import 'package:flutter/material.dart';

/// Shared visual tokens aligned with the 99chat product surfaces.
///
/// New pages should consume these semantic tokens instead of scattering raw
/// colors and dimensions through page code. Existing OpenIM screens can keep
/// using [Styles] until they are migrated.
class AppTokens {
  AppTokens._();

  // Semantic colors.
  static const Color accent = Color(0xFF1E90FF);
  static const Color ink600 = Color(0xFF374151);
  static const Color danger = Color(0xFFDC2626);
  static const Color walletDanger = Color(0xFFE60022);
  static const Color success = Color(0xFF059669);
  static const Color biometricGreen = Color(0xFF07C160);
  static const Color warning = Color(0xFFD97706);
  static const Color backgroundLight = Color(0xFFF5F6F8);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceAltLight = Color(0xFFF1F3F5);
  static const Color textPrimaryLight = Color(0xFF1C1C1E);
  static const Color textSecondaryLight = Color(0xFF7B8491);
  static const Color borderLight = Color(0xFFE6E8EC);

  static const Color backgroundDark = Color(0xFF101114);
  static const Color surfaceDark = Color(0xFF1B1D22);
  static const Color surfaceAltDark = Color(0xFF23262D);
  static const Color textPrimaryDark = Color(0xFFF4F4F4);
  static const Color textSecondaryDark = Color(0xFF9A9CA3);
  static const Color borderDark = Color(0xFF2A2D33);

  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color profileSignatureBgLight = Color(0xFFEDEBFF);
  static const Color profileSignatureBgDark = Color(0xFF5D74F2);
  static const Color profileSignatureTextLight = Color(0xFF5D74F2);
  static const Color profileSignatureTextDark = Color(0xFFA8B4FF);
  static const Color decorativeSparkle = Color(0xFF8EBBFF);
  static const Color profileEcoGlowLight = Color(0xFFF2DFFF);
  static const Color profileEcoGlowDark = Color(0xFF6B4A9A);

  static const double profileSectionLightOpacity = 0.72;
  static const double profileSectionDarkOpacity = 0.94;

  static const List<Color> decorativeGradientLight = [
    Color(0xFFFCFCFE),
    Color(0xFFFAF9FD),
    Color(0xFFFAFBFC),
  ];
  static const List<Color> decorativeGradientDark = [
    Color(0xFF1C1830),
    Color(0xFF171A24),
    Color(0xFF131820),
    Color(0xFF101114),
  ];
  static const List<double> decorativeGradientDarkStops = [0, 0.36, 0.72, 1];

  static Color background({required bool dark}) =>
      dark ? backgroundDark : backgroundLight;
  static Color surface({required bool dark}) =>
      dark ? surfaceDark : surfaceLight;
  static Color surfaceAlt({required bool dark}) =>
      dark ? surfaceAltDark : surfaceAltLight;
  static Color textPrimary({required bool dark}) =>
      dark ? textPrimaryDark : textPrimaryLight;
  static Color textSecondary({required bool dark}) =>
      dark ? textSecondaryDark : textSecondaryLight;
  static Color border({required bool dark}) =>
      dark ? borderDark : borderLight;

  // 4pt spacing scale used by 99chat surfaces.
  static const double s2 = 4;
  static const double s3 = 8;
  static const double s4 = 12;
  static const double s5 = 16;
  static const double s6 = 20;
  static const double s7 = 24;
  static const double s8 = 32;

  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 14;
  static const double rPill = 999;

  static const double listItemHeight = 56;
  static const double mainTabTitleFontSize = 22;
  static const double mainTabTitleVerticalOffset = -2;
  static const double profileNameFontSize = 19;
  static const double listTitleFontSize = 17;
  static const double secondaryFontSize = 15;
  static const double captionFontSize = 14;
  static const double profileAvatarSize = 72;
  static const double profileMenuIconSize = 28;
  static const double profileQrIconSize = 20;
  static const double mainTabIndicatorWidth = 32;
  static const double mainTabIndicatorDesktopWidth = 36;
  static const double mainTabIndicatorHeight = 4;
  static const double mainTabIndicatorDotSize = 8;
  static const double mainTabIndicatorGap = 8;
  static const double mainTabIndicatorTitleGap = 2;
  static const double chevronSize = 24;
}

/// Six-digit transaction password setup and numeric input surfaces.
class TradePasswordTokens {
  TradePasswordTokens._();

  static const double contentMaxWidth = 480;
  static const double logoSize = 80;
  static const double logoRadius = 16;
  static const double headingFontSize = 20;
  static const double helperFontSize = 14;
  static const double securityFontSize = 12;
  static const double digitFontSize = 24;
  static const double cellMaxSize = 48;
  static const double cellGap = 6;
  static const double dotSize = 9;
  static const double keyMinHeight = 48;
  static const double keyMaxHeight = 56;
  static const double keyHeightScreenRatio = 0.064;
  static const double deleteIconSize = 24;
  static const double securityIconSize = 20;
  static const Duration inputAnimation = Duration(milliseconds: 120);
}
