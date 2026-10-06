import 'package:flutter/material.dart';

import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';

abstract final class WalletRecordTokens {
  static const double maxWidth = 680;
  static const double title = 18;
  static const double body = 14;
  static const double amount = 16;
  static const double caption = 12;
  static const double month = 32;
  static const double avatar = 36;
  static const double minTap = 48;
  static const double rowHeight = 72;
  static const double divider = 1;
  static const double tabIndicator = 36;
  static const double indicatorHeight = 2;
  static const double emptyImage = 104;
  static const double filterWidth = 480;
  static const double filterTitle = 20;
  static const Color incomeLight = Color(0xFFC64D00);
  static const Color incomeDark = Color(0xFFFF9148);

  static Color selectedTab(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? WalletPageColors.of(context).blue
          : const Color(0xFF146BC7);

  static Color failure(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? const Color(0xFFFF647A)
          : WalletPageColors.of(context).red;

  static Color income(BuildContext context) =>
      WalletPageColors.of(context).dark ? incomeDark : incomeLight;

  static Color muted(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return Color.lerp(colors.text, colors.subText, .72)!;
  }

  static ButtonStyle iconStyle(BuildContext context) => IconButton.styleFrom(
        minimumSize: const Size.square(minTap),
        foregroundColor: WalletPageColors.of(context).text,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rSm)),
      );
}
