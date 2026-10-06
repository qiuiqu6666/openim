import '../wallet_99chat_tokens.dart';

/// Geometry shared by wallet deposit and withdrawal currency pickers.
abstract final class WalletCoinPickerTokens {
  static const maxWidth = 480.0;
  static const titleFont = 17.0;
  static const bodyFont = 14.0;
  static const codeFont = 18.0;
  static const nameFont = 13.0;
  static const headingFont = 14.0;
  static const indexFont = 12.0;
  static const rowMinHeight = AppTokens.listItemHeight + AppTokens.s4;
  static const minTap = AppTokens.buttonHeight;
  static const scrollDuration = Duration(milliseconds: 220);
}
