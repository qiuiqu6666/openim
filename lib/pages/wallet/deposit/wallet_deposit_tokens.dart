import 'package:flutter/material.dart';

import '../widgets/wallet_99chat_tokens.dart';

abstract final class WalletDepositTokens {
  static const double maxWidth = 480;
  static const double qrSize = 168;
  static const double qrLogo = 24;
  static const double qrQuietZone = 16;
  static const double detailText = 14;
  static const double minTap = AppTokens.buttonHeight;
  static const double title = 24;
  static const double body = 15;
  static const double caption = 12;
  static const Color qrBackground = AppTokens.surfaceLight;
  static const Color qrInk = AppTokens.ink900;
}
