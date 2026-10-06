import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/home/widgets/wallet_asset_value_sort.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

CoinDto coin(String code, String fiat, {bool platform = false}) => CoinDto(
    name: code,
    code: code,
    sub: '',
    bal: '0',
    fiat: fiat,
    type: CoinType.trx,
    platformCoin: platform);
void main() {
  test('sorts all coins by exact CNY value, with stable ties and unknown last',
      () {
    final source = [
      coin('99', '¥1.00', platform: true),
      coin('USDT', '¥9,007,199,254,740,992.02'),
      coin('TRX', '¥9,007,199,254,740,992.01'),
      coin('TIE', '¥1.00'),
      coin('ZERO', '0.00'),
      coin('UNKNOWN', '--')
    ];
    expect(sortWalletAssetsByValue(source, descending: true).map((c) => c.code),
        ['USDT', 'TRX', '99', 'TIE', 'ZERO', 'UNKNOWN']);
    expect(
        sortWalletAssetsByValue(source, descending: false).map((c) => c.code),
        ['ZERO', '99', 'TIE', 'TRX', 'USDT', 'UNKNOWN']);
    expect(source.first.code, '99');
  });
}
