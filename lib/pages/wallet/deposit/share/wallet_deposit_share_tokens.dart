import 'package:flutter/material.dart';

import '../../widgets/wallet_99chat_tokens.dart';

/// Deposit sharing keeps the captured image separate from sheet actions.
abstract final class WalletDepositShareTokens {
  static const double sheetRadius = 16;
  static const double previewHorizontalInset = 28;
  static const double maxWidth = 480;
  static const double cardMaxWidth = 360;
  static const double actionCircleSize = 44;
  static const double actionItemWidth = 72;
  static const double actionIconSize = 24;
  static const double actionVerticalPadding = 4;
  static const double actionLabelGap = 8;
  static const double actionLabelSize = 12;
  static const double panelTitleSize = 18;
  static const double cancelSeparatorHeight = 6;
  static const double cancelHeight = 52;
  static const double cancelTextSize = 16;
  static const double panelPadding = 16;
  static const double panelGap = 12;
  static const double previewBottomGap = 30;

  static const double cardRadius = 16;
  static const double cardPadding = 16;
  static const double cardBottomPadding = 32;
  static const double brandLogoSize = 28;
  static const double brandGap = 8;
  static const double brandFontSize = 20;
  static const double timestampFontSize = 11;
  static const double headerGap = 12;
  static const double dividerGap = 16;
  static const double titleTopGap = 32;
  static const double titleFontSize = 15;
  static const double titleQrGap = 18;
  static const double qrSize = 150;
  static const double qrQuietZone = 16;
  static const double qrRadius = 12;
  static const double qrDetailsGap = 40;
  static const double detailFontSize = 12;
  static const double detailLabelWidth = 72;
  static const double detailColumnGap = 12;
  static const double detailRowGap = 12;
  static const double detailLineHeight = 1.4;
  static const String brandLogo = 'assets/img/99chat_logo.png';

  static Color cardColor({required bool dark}) =>
      dark ? AppTokens.surfaceAltDark : AppTokens.ink50;
  static Color dividerColor({required bool dark}) =>
      dark ? AppTokens.borderDark : AppTokens.ink150;
}
