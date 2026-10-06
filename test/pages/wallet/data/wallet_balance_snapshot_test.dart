import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';

import 'wallet_fund_test_transport.dart';

void main() {
  late WalletFundTestTransport transport;
  setUp(() => transport = WalletFundTestTransport());
  tearDown(() => transport.close());

  Map<String, dynamic> response({num? rate = 6.7064, String usdt = '12.5'}) => {
        'balances': [
          {
            'currency': 'USDT',
            'available': usdt,
            'frozen': '4',
            'valueCny': rate == null ? null : '84.00',
            'changeAmountCny': '24.00',
            'changePercent': '40.00'
          },
          {'currency': 'TRX', 'available': '10', 'frozen': '0'},
          {'currency': 'BI99', 'available': '0', 'frozen': '0'},
        ],
        'totalCny': rate == null ? null : '110.00',
        'dailyChange': {
          'status': rate == null ? 'unavailable' : 'ready',
          'amountCny': '35.00',
          'percentage': '46.67'
        },
        'usdToThisRate': rate,
        'usdToThisRateUpdatedAt': rate == null ? null : 1791248331897,
      };

  test('balances and supplied rate populate wallet valuation in one request',
      () async {
    transport.respond(response());
    final repo = WalletFundRepository(
        api: transport.wallet, accountProvider: () => 'server:user');
    final wallet = await repo.getWallet();
    expect(wallet.totalBal, '110.00');
    expect(wallet.coins.map((c) => c.bal), ['12.50', '10.00', '0.00']);
    expect(wallet.coins.first.fiat, '¥84.00');
    expect(wallet.coins.first.frozen, '4');
    expect(wallet.dailyAmountCny, '35.00');
    expect(wallet.dailyPercentage, '46.67');
    expect(wallet.coins.first.changePercent, '40.00');
    expect(wallet.coins.skip(1).every((c) => c.fiat == '--'), isTrue);
    expect(transport.requests, hasLength(1));
  });

  test('missing rate clears valuation while preserving balances', () async {
    final repo = WalletFundRepository(
        api: transport.wallet, accountProvider: () => 'server:user');
    transport.respond(response());
    expect((await repo.getWallet()).totalBal, '110.00');
    transport.respond(response(rate: null));
    final wallet = await repo.getWallet();
    expect(wallet.totalBal, '--');
    expect(wallet.dailyAmountCny, '--');
    expect(wallet.dailyPercentage, '--');
    expect(wallet.coins.first.availableRaw, '12.5');
    expect(wallet.coins.every((c) => c.fiat == '--'), isTrue);
  });

  test('timestamp, zero, negative and large decimal valuations are retained',
      () async {
    for (final entry in {
      '0': '0.00',
      '-0.015001': '-0.10',
      '123456789012345678.123456': '827950609832395055.77',
    }.entries) {
      transport.respond(response(usdt: entry.key));
      final snapshot = await transport.wallet.fetchBalanceSnapshot();
      expect(snapshot.usdtCnyValue, entry.value);
      expect(snapshot.usdToThisRateUpdatedAt, 1791248331897);
    }
  });
}
