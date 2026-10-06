import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/deposit/coin_picker/wallet_deposit_coin.dart';

import 'support/wallet_deposit_coin_test_support.dart';

void main() {
  test('supported deposit labels come from endpoint currencies and contract',
      () {
    final coins = WalletDepositCoin.fromAddress(depositAddressFixture());
    expect(coins.map((coin) => coin.currency),
        [FundCurrency.usdt, FundCurrency.trx]);
    expect(coins.first.contractAddress, testUsdtContract);
    expect(coins.last.contractAddress, isEmpty);
    final trxOnly = WalletDepositAddress.fromJson({
      'status': 'pending',
      'network': 'TRON',
      'address': '',
      'currencies': ['TRX'],
      'confirmations': 19,
      'usdtContract': '',
    });
    expect(WalletDepositCoin.fromAddress(trxOnly).map((coin) => coin.code),
        ['TRX']);
  });

  test('search matches trimmed case-insensitive code, name and server contract',
      () {
    final coins = WalletDepositCoin.fromAddress(depositAddressFixture());
    for (final query in [
      'usdt',
      ' UsDt ',
      'TETHER',
      testUsdtContract.toLowerCase()
    ]) {
      expect(
          coins.where((coin) => coin.matches(query)).map((coin) => coin.code),
          ['USDT']);
    }
    for (final query in [' trx ', 'tRoN']) {
      expect(
          coins.where((coin) => coin.matches(query)).map((coin) => coin.code),
          ['TRX']);
    }
    expect(coins.where((coin) => coin.matches('unknown-contract')), isEmpty);
    expect(coins.where((coin) => coin.matches('  ')), hasLength(2));
  });

  test(
      'invalid deposit capabilities are rejected instead of offering static rows',
      () {
    final json = <String, dynamic>{
      'status': 'ready',
      'network': 'TRON',
      'address': testDepositAddress,
      'currencies': ['USDT'],
      'confirmations': 19,
      'usdtContract': testUsdtContract,
    };
    for (final invalid in [
      {
        ...json,
        'currencies': ['BI99']
      },
      {
        ...json,
        'currencies': ['BTC']
      },
      {...json, 'currencies': <String>[]},
      {...json, 'usdtContract': ''},
    ]) {
      expect(
          () => WalletDepositAddress.fromJson(invalid), throwsFormatException);
    }
  });
}
