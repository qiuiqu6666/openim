import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';

Map<String, dynamic> quoteFixture() => {
      'quoteID': 'sq-test-1',
      'fromCurrency': 'USDT',
      'toCurrency': 'TRX',
      'amount': '10',
      'estimatedReceived': '29',
      'rate': '2.900000010000000000',
      'marketRate': '3.000000000000000000',
      'adjustmentPercent': '-3.333333',
      'inputValueUsd': '10.00',
      'expiresAt': 1791252030000,
    };

void main() {
  test('documented quote preserves rates and exact input and expiry', () {
    final quote = WalletSwapQuote.fromJson(quoteFixture());
    expect(quote.quoteID, 'sq-test-1');
    expect(quote.fromCurrency, FundCurrency.usdt);
    expect(quote.toCurrency, FundCurrency.trx);
    expect(quote.amount, FundAmount.parse('10', FundCurrency.usdt));
    expect(quote.estimatedReceived, FundAmount.parse('29', FundCurrency.trx));
    expect(quote.rate, '2.900000010000000000');
    expect(quote.marketRate, '3.000000000000000000');
    expect(quote.adjustmentPercent, '-3.333333');
    expect(quote.inputValueUsd, '10.00');
    expect(quote.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1791252030000, isUtc: true));
    expect(
        quote.matches(
            FundAmount.parse('10.000000', FundCurrency.usdt), FundCurrency.trx),
        true);
    expect(
        quote.matches(
            FundAmount.parse('10.000001', FundCurrency.usdt), FundCurrency.trx),
        false);
    expect(
        quote.matches(
            FundAmount.parse('10', FundCurrency.trx), FundCurrency.usdt),
        false);
    expect(
        quote.isExpired(
            quote.expiresAt.subtract(const Duration(milliseconds: 1))),
        false);
    expect(quote.isExpired(quote.expiresAt), true);
  });

  test('received is truncated to target precision using the saved exact rate',
      () {
    final json = quoteFixture()
      ..addAll({
        'toCurrency': 'BI99',
        'amount': '1.234567',
        'estimatedReceived': '3.58',
        'inputValueUsd': null,
      });
    final quote = WalletSwapQuote.fromJson(json);
    expect(quote.estimatedReceived.units, BigInt.from(358));
    expect(quote.inputValueUsd, null);
    expect(() => WalletSwapQuote.fromJson(json..['estimatedReceived'] = '3.59'),
        throwsFormatException);
  });

  test('large amounts and a target precision boundary never use floating point',
      () {
    final json = quoteFixture()
      ..addAll({
        'amount': '9223372036854.775807',
        'estimatedReceived': '9223372036854.775807',
        'rate': '1.000000000000000000',
        'marketRate': '1.000000000000000000',
        'adjustmentPercent': '0',
        'inputValueUsd': null,
      });
    expect(WalletSwapQuote.fromJson(json).estimatedReceived.units,
        BigInt.parse('9223372036854775807'));
    json.addAll({
      'amount': '0.000001',
      'toCurrency': 'BI99',
      'estimatedReceived': '0.01',
      'rate': '10000.000000000000000000',
    });
    expect(WalletSwapQuote.fromJson(json).estimatedReceived.units, BigInt.one);
    json['rate'] = '9999.999999999999999999';
    expect(() => WalletSwapQuote.fromJson(json), throwsFormatException);
  });

  test('all six supported directions obey their source and target precision',
      () {
    for (final from in FundCurrency.values) {
      for (final to in FundCurrency.values.where((value) => value != from)) {
        final quote = WalletSwapQuote.fromJson(quoteFixture()
          ..addAll({
            'fromCurrency': from.code,
            'toCurrency': to.code,
            'amount': '0.01',
            'estimatedReceived': '0.01',
            'rate': '1.000000000000000000',
          }));
        expect(quote.matches(FundAmount.parse('0.01', from), to), true);
      }
    }
  });

  test('malformed quotes cannot silently become a zero or an inferred price',
      () {
    final invalid = <Map<String, dynamic>>[
      {'quoteID': ''},
      {'quoteID': ' sq-test-1 '},
      {'quoteID': 1},
      {'fromCurrency': 'USDC'},
      {'toCurrency': 'USDT'},
      {'amount': '0'},
      {'amount': 10},
      {'amount': '10.0000001'},
      {'amount': ' 10 '},
      {'estimatedReceived': '0'},
      {'estimatedReceived': '29.0000001'},
      {'estimatedReceived': '29.000001'},
      {'estimatedReceived': 29},
      {'rate': '2.9'},
      {'rate': '2.9000000100000000000'},
      {'rate': '2.9e0'},
      {'rate': 2.9},
      {'rate': '0.000000000000000000'},
      {'marketRate': '-1.000000000000000000'},
      {'marketRate': '0.000000000000000000'},
      {'adjustmentPercent': '-99.000001'},
      {'adjustmentPercent': '100.000001'},
      {'adjustmentPercent': '1.0000001'},
      {'adjustmentPercent': '+1'},
      {'adjustmentPercent': 0},
      {'inputValueUsd': '10'},
      {'inputValueUsd': '10.000'},
      {'inputValueUsd': '-0.01'},
      {'inputValueUsd': 10.0},
      {'expiresAt': '1791252030000'},
      {'expiresAt': 1791252030000.0},
      {'expiresAt': 0},
      {'expiresAt': 8640000000000001},
    ];
    for (final change in invalid) {
      expect(() => WalletSwapQuote.fromJson(quoteFixture()..addAll(change)),
          throwsFormatException,
          reason: '$change');
    }
    for (final key in [
      'rate',
      'marketRate',
      'quoteID',
      'amount',
      'expiresAt'
    ]) {
      expect(() => WalletSwapQuote.fromJson(quoteFixture()..remove(key)),
          throwsFormatException,
          reason: 'missing $key');
    }
  });

  test('adjustment endpoints and an unavailable USD value remain valid', () {
    for (final adjustment in ['-99', '-99.000000', '100', '100.000000', '0']) {
      final quote = WalletSwapQuote.fromJson(quoteFixture()
        ..addAll({'adjustmentPercent': adjustment, 'inputValueUsd': null}));
      expect(quote.adjustmentPercent, adjustment);
    }
    expect(
        WalletSwapQuote.fromJson(quoteFixture()..['inputValueUsd'] = '0.00')
            .inputValueUsd,
        '0.00');
  });
}
