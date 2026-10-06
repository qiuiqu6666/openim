import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';

import '../wallet_fund_test_transport.dart';

void main() {
  test('authenticated address reads expose freshly effective currency rules',
      () async {
    final transport = WalletFundTestTransport();
    addTearDown(transport.close);
    transport.respond(walletTestAddress());
    final first = await transport.wallet.fetchDepositAddress();
    expect(first.ruleFor(FundCurrency.usdt)!.minWithdrawAmount, '10');
    expect(first.ruleFor(FundCurrency.usdt)!.withdrawFee, '0.000001');
    expect(
        first.ruleFor(FundCurrency.trx)!.withdrawFeeCurrency, FundCurrency.trx);
    final latest = walletTestAddress();
    final rules = latest['currencyRules'] as Map<String, dynamic>;
    (rules['USDT'] as Map<String, dynamic>).addAll({
      'minWithdrawAmount': '12.000001',
      'withdrawFee': '0.123456',
      'estimatedArrivalSeconds': 180,
      'memoRequired': true,
    });
    transport.respond(latest);
    final next = await transport.wallet.fetchDepositAddress();
    expect(next.address, first.address);
    final effective = next.ruleFor(FundCurrency.usdt)!;
    expect(effective.minWithdrawAmount, '12.000001');
    expect(effective.withdrawFee, '0.123456');
    expect(effective.estimatedArrivalSeconds, 180);
    expect(effective.memoRequired, true);
    expect(first.ruleFor(FundCurrency.usdt)!.withdrawFee, '0.000001');
    expect(transport.requests, hasLength(2));
    for (final request in transport.requests) {
      expect(request.method, 'GET');
      expect(request.path, endsWith('/chat/fund/deposit-address'));
      expect(request.headers['token'], 'chat-token');
      expect(request.data, isNull);
    }
    expect(transport.requests.map((r) => r.headers['operationID']).toSet(),
        hasLength(2));
  });
}
