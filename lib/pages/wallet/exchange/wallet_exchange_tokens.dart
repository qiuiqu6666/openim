import 'package:flutter/material.dart';

import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';

/// Screenshot-specific geometry stays local to the exchange module.
abstract final class WalletExchangeTokens {
  static const double maxWidth = 560;
  static const double amountFont = 56;
  static const double amountMinFont = 32;
  static const double currencyFont = 22;
  static const double amountLineHeight = 1.15;
  static const double bodyFont = 16;
  static const double captionFont = 12;
  static const double keypadFont = 26;
  static const double coinSize = 36;
  static const double rowHeight = 64;
  static const double keyHeight = 52;
  static const double caretWidth = 2;
  static const double fixedFooterMinHeight = 650;
  static const double stackedCurrencyWidth = 280;
  static const double footerTextScaleLimit = 1.35;

  static Color background(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return colors.dark ? colors.bg : colors.card;
  }

  static Color panel(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return colors.dark ? colors.card : colors.bg;
  }

  static Color estimate(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? const Color(0xFF8CCA84)
          : const Color(0xFF287421);

  static Color action(BuildContext context) =>
      AppTokens.appTextPrimary(WalletPageColors.of(context).dark);

  static Color onAction(BuildContext context) =>
      WalletPageColors.of(context).dark
          ? AppTokens.backgroundDark
          : AppTokens.surfaceLight;
}
