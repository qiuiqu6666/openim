import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';

import 'wallet_fund_test_transport.dart';

void main() {
  test(
      'balance rollbacks retain exact signed amounts without enabling negative spending',
      () {
    for (final entry in [
      (FundCurrency.usdt, '-0.000001', '-0.000001'),
      (FundCurrency.trx, '-1.500000', '-1.5'),
      (FundCurrency.bi99, '-0.01', '-0.01'),
      (FundCurrency.bi99, '-10', '-10'),
      (FundCurrency.usdt, '-9223372036854.775807', '-9223372036854.775807'),
    ]) {
      final balance = FundBalance.fromJson({
        'currency': entry.$1.code,
        'available': entry.$2,
        'frozen': '0',
      }, allowNegativeAvailable: true);
      expect(balance.available.decimal, entry.$3);
      expect(balance.available.isPositive, false);
      expect(balance.available.units.isNegative, true);
      expect(() => FundAmount.parse(entry.$2, entry.$1), throwsFormatException);
      expect(
          () => FundBalance.fromJson({
                'currency': entry.$1.code,
                'available': entry.$2,
                'frozen': '0',
              }),
          throwsFormatException);
    }
    final balance = FundBalance.fromJson(
        {'currency': 'BI99', 'available': '-1', 'frozen': '0'},
        allowNegativeAvailable: true);
    expect(balance.available.displayDecimal, '-1.00');
    expect(
        FundBalance.fromJson(
                {'currency': 'USDT', 'available': '-0', 'frozen': '0'},
                allowNegativeAvailable: true)
            .available
            .decimal,
        '0');
  });

  test('balances reject malformed signed values and negative frozen funds', () {
    for (final value in [
      '--1',
      '-.5',
      '- 1',
      '-1.0000001',
      '+1',
      '1e2',
      '-1,2'
    ]) {
      expect(
          () => FundBalance.fromJson(
              {'currency': 'USDT', 'available': value, 'frozen': '0'},
              allowNegativeAvailable: true),
          throwsFormatException);
    }
    expect(
        () => FundBalance.fromJson(
            {'currency': 'USDT', 'available': '1', 'frozen': '-1'}),
        throwsFormatException);
  });

  test(
      'deposit address rejects unsupported currencies, networks and invalid readiness',
      () {
    for (final change in <Map<String, dynamic>>[
      {
        'currencies': ['USDT', 'BI99']
      },
      {
        'currencies': ['BTC']
      },
      {
        'currencies': ['USDT', 'USDT']
      },
      {'network': 'Ethereum'},
      {'status': 'unknown'},
      {'address': ''},
      {'confirmations': -1},
      {'usdtContract': ''},
    ]) {
      expect(
          () => WalletDepositAddress.fromJson(
              walletTestAddress()..addAll(change)),
          throwsFormatException);
    }
  });

  test(
      'deposits cannot fabricate pending events or accept rounded numeric amounts',
      () {
    for (final change in <Map<String, dynamic>>[
      {'amount': 12.5},
      {'amount': '-1'},
      {'amount': '0'},
      {'amount': '0.0000001'},
      {'currency': 'BI99'},
      {'currency': 'BTC'},
      {'status': 'pending'},
      {'height': 10.5},
      {'confirmations': true},
    ]) {
      expect(
          () => WalletDepositRecord.fromJson(
              walletTestDeposit()..addAll(change),
              occurrenceIndex: 0),
          throwsFormatException);
    }
  });

  test(
      'wallet order timestamps are Unix milliseconds and remain absent when unknown',
      () {
    for (final value in [1791032141597, '1791032141597', 1791000000]) {
      final order =
          WalletFundOrder.fromJson(walletTestOrder()..['createdAt'] = value);
      expect(
          order.createdAt,
          DateTime.fromMillisecondsSinceEpoch(int.parse(value.toString()),
              isUtc: true));
    }
    for (final value in [null, '', 0, '0']) {
      expect(
          WalletFundOrder.fromJson(walletTestOrder()..['createdAt'] = value)
              .createdAt,
          null);
    }
    for (final value in [true, 1.2, '-1', 'bad-time']) {
      expect(
          () => WalletFundOrder.fromJson(
              walletTestOrder()..['createdAt'] = value),
          throwsFormatException);
    }
  });

  test(
      'orders preserve exact optional real fields and reject invalid wallet states',
      () {
    final order = WalletFundOrder.fromJson(walletTestOrder(
        biz: 'swap', status: 'done')
      ..addAll(
          {'targetCurrency': 'BI99', 'targetAmount': '999999999999999999.99'}));
    expect(order.targetAmount, '999999999999999999.99');
    expect(order.fee, null);
    expect(order.createdAt, null);
    for (final change in <Map<String, dynamic>>[
      {'biz': 'unknown'},
      {'status': 'done'},
      {'currency': 'BTC'},
      {'amount': 10},
      {'fee': -1},
      {'targetCurrency': 'BTC'},
      {'targetCurrency': 'BI99', 'targetAmount': '1.001'},
    ]) {
      expect(() => WalletFundOrder.fromJson(walletTestOrder()..addAll(change)),
          throwsFormatException);
    }
    final unusedTarget = WalletFundOrder.fromJson(
        walletTestOrder()..addAll({'targetCurrency': '', 'targetAmount': '0'}));
    expect(unusedTarget.targetCurrency, null);
    expect(unusedTarget.targetAmount, null);
  });
}
