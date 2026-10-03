import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

CoinDto coin({required String fiat, int balMinor = 1}) => CoinDto(
      name: 'USDT',
      sub: '',
      bal: '0',
      fiat: fiat,
      type: CoinType.usdt,
      code: 'USDT',
      balMinor: balMinor,
      scale: 6,
    );

void main() {
  test('99chat small-asset threshold is strictly below CNY 1', () {
    expect(coin(fiat: '¥0.99').isSmallAsset, isTrue);
    expect(coin(fiat: '¥1.00').isSmallAsset, isFalse);
    expect(coin(fiat: '≈ ¥0.50').isSmallAsset, isTrue);
  });

  test('unknown valuation is not treated as a verified small asset', () {
    expect(coin(fiat: '--', balMinor: 0).isSmallAsset, isFalse);
    expect(coin(fiat: '--', balMinor: 1).isSmallAsset, isFalse);
  });

  test('unavailable repository never fabricates wallet data', () async {
    const repo = UnavailableWalletRepository();
    expect(repo.getWallet(), throwsA(isA<WalletBackendUnavailableException>()));
    expect(repo.getPayMethods(), throwsA(isA<WalletBackendUnavailableException>()));
  });
}
