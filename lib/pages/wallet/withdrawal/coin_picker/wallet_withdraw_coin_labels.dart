import '../../host/wallet_i18n.dart';
import '../../wallet_repository.dart';

/// Display labels leave the server's coin and payment DTOs unchanged.
abstract final class WalletWithdrawCoinLabels {
  static String code(CoinDto coin) => coin.platformCoin
      ? '99'
      : (coin.code.trim().isEmpty ? coin.name.trim() : coin.code.trim())
          .toUpperCase();

  static String name(CoinDto coin, AppI18n i18n) {
    final symbol = code(coin);
    final original = coin.name.trim();
    if (coin.platformCoin) {
      return i18n.t(
          zhHans: '平台币',
          zhHant: '平台幣',
          en: 'Platform coin',
          ja: 'プラットフォーム通貨',
          ko: '플랫폼 코인');
    }
    if (symbol == 'USDT') return 'Tether';
    if (symbol == 'TRX') return 'TRON';
    return original.isEmpty ? symbol : original;
  }

  static bool matches(CoinDto coin, String query, AppI18n i18n) {
    final value = query.trim().toLowerCase();
    return code(coin).toLowerCase().contains(value) ||
        coin.name.toLowerCase().contains(value) ||
        name(coin, i18n).toLowerCase().contains(value);
  }
}
