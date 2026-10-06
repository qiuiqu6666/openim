import 'package:flutter/material.dart';

import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';

/// Layout values specific to the wallet overview. Core surfaces and spacing
/// continue to use the app's existing wallet theme.
abstract final class WalletHomeTokens {
  static const double maxWidth = 680;
  static const double wideBreakpoint = 840;
  static const double sectionTitle = 16;
  static const double withdrawSheetTitle = 18;
  static const double body = 14;
  static const double caption = 12;
  static const double rowAmount = 16;
  static const double totalAmount = 28;
  static const double icon = 20;
  static const double coinLogo = 36;
  static const double assetRowHeight = 72;
  static const double minTap = 48;
  static const double primaryActionHeight = 48;
  static const double progressSize = 20;
  static const double progressStroke = 2;
  static const double emptyIllustration = 104;
  static const double divider = 1;
  static const double trendPlotHeight = 140;
  static const trendPeriods = [7, 30, 90, 180, 360];
  static const Color trendAccent = Color(0xFF68C900);
  static const Color trendIconLight = Color(0xFF4B9F00);

  // A deeper shade of the existing brand blue keeps white button labels and
  // small blue text readable. The shared app accent itself is unchanged.
  static const Color primaryAction = Color(0xFF146BC7);
  static const Color onPrimaryAction = AppTokens.surfaceLight;
  static const Color darkAccentText = Color(0xFF8EBBFF);
  static const Color dailyIncreaseLight = Color(0xFF047857);
  static const Color dailyIncreaseDark = Color(0xFF34D399);
  static const Color dailyDecreaseLight = Color(0xFFB91C1C);
  static const Color dailyDecreaseDark = Color(0xFFF87171);

  static Color dailyIncrease(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? dailyIncreaseDark
          : dailyIncreaseLight;

  static Color dailyDecrease(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? dailyDecreaseDark
          : dailyDecreaseLight;

  static Color overviewAction(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? AppTokens.textPrimaryDark
          : AppTokens.textPrimaryLight;

  static Color onOverviewAction(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? AppTokens.backgroundDark
          : AppTokens.surfaceLight;

  // Keep the selected outline readable on white while matching the green frame.
  static Color trendIcon(BuildContext context) =>
      WalletPageColors.of(context).dark ? trendAccent : trendIconLight;

  static Color accentText(BuildContext context) =>
      WalletPageColors.of(context).dark ? darkAccentText : primaryAction;

  static Color muted(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return Color.lerp(colors.text, colors.subText, .72)!;
  }
}
