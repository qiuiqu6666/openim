import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_models.dart';
import 'package:openim/services/fund_models.dart';

Map<String, dynamic> _addressJson() => {
      'status': 'ready',
      'network': 'TRON',
      'address': 'unchanged-deposit-address',
      'currencies': ['TRX'],
      'confirmations': 19,
      'usdtContract': '',
    };

void main() {
  test('full rules preserve exact server amounts and optional values', () {
    final rule = WalletCurrencyRule.fromJson({
      'minDepositAmount': '0001.000001',
      'minWithdrawAmount': '9223372036854.775807',
      'withdrawFee': '0.250000',
      'withdrawFeeCurrency': 'USDT',
      'receivingAccountType': 'wallet',
      'estimatedArrivalSeconds': 300,
      'withdrawUnlockConfirmations': 64,
      'memoRequired': false,
    }, currency: FundCurrency.usdt);
    expect(rule.minDepositAmount, '0001.000001');
    expect(rule.minWithdrawAmount, '9223372036854.775807');
    expect(rule.withdrawFee, '0.250000');
    expect(rule.withdrawFeeCurrency, FundCurrency.usdt);
    expect(rule.receivingAccountType, 'wallet');
    expect(rule.estimatedArrivalSeconds, 300);
    expect(rule.withdrawUnlockConfirmations, 64);
    expect(rule.memoRequired, isFalse);
    expect(rule.isWithdrawalComplete, isTrue);
  });

  test('missing and null fields remain unknown rather than zero or false', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {
        'minDepositAmount': null,
        'minWithdrawAmount': null,
        'withdrawFee': null,
        'withdrawFeeCurrency': null,
        'receivingAccountType': null,
        'estimatedArrivalSeconds': null,
        'withdrawUnlockConfirmations': null,
        'memoRequired': null,
      },
    ]) {
      final rule =
          WalletCurrencyRule.fromJson(json, currency: FundCurrency.trx);
      expect(rule.minDepositAmount, isNull);
      expect(rule.minWithdrawAmount, isNull);
      expect(rule.withdrawFee, isNull);
      expect(rule.withdrawFeeCurrency, isNull);
      expect(rule.receivingAccountType, isNull);
      expect(rule.estimatedArrivalSeconds, isNull);
      expect(rule.withdrawUnlockConfirmations, isNull);
      expect(rule.memoRequired, isNull);
      expect(rule.isWithdrawalComplete, isFalse);
    }
  });

  test('withdraw completeness requires all fields but accepts explicit zeros',
      () {
    final complete = <String, dynamic>{
      'minWithdrawAmount': '0',
      'withdrawFee': '0.000000',
      'withdrawFeeCurrency': 'TRX',
    };
    for (final field in complete.keys) {
      expect(
        WalletCurrencyRule.fromJson({...complete, field: null},
                currency: FundCurrency.trx)
            .isWithdrawalComplete,
        isFalse,
      );
    }
    final rule = WalletCurrencyRule.fromJson({
      ...complete,
      'minDepositAmount': '0',
      'estimatedArrivalSeconds': 0,
      'withdrawUnlockConfirmations': 0,
      'memoRequired': false,
    }, currency: FundCurrency.trx);
    expect(rule.isWithdrawalComplete, isTrue);
    expect(rule.minDepositAmount, '0');
    expect(rule.estimatedArrivalSeconds, 0);
    expect(rule.withdrawUnlockConfirmations, 0);
    expect(rule.memoRequired, isFalse);
  });

  test('each monetary field rejects numeric, signed and malformed decimals',
      () {
    for (final field in [
      'minDepositAmount',
      'minWithdrawAmount',
      'withdrawFee',
    ]) {
      for (final value in [
        1,
        1.2,
        '',
        ' 1',
        '1 ',
        '1\n',
        '+1',
        '-1',
        '-0',
        '.1',
        '1.',
        '1e2',
        '1,000',
        'NaN',
        'Infinity',
        '1.0000001',
      ]) {
        expect(
          () => WalletCurrencyRule.fromJson({field: value},
              currency: FundCurrency.usdt),
          throwsFormatException,
          reason: '$field must reject $value',
        );
      }
    }
  });

  test(
      'currency precision is exact and large values never pass through doubles',
      () {
    for (final currency in FundCurrency.values) {
      final smallest = '0.${'0' * (currency.decimals - 1)}1';
      final excess = '0.${'0' * currency.decimals}1';
      expect(
        WalletCurrencyRule(currency: currency, withdrawFee: smallest)
            .withdrawFee,
        smallest,
      );
      expect(
        () => WalletCurrencyRule(currency: currency, withdrawFee: excess),
        throwsFormatException,
      );
      final large = '999999999999999999999999999.${'9' * currency.decimals}';
      expect(
        WalletCurrencyRule(currency: currency, minDepositAmount: large)
            .minDepositAmount,
        large,
      );
    }
  });

  test('fee currency mismatches are rejected by wire and direct constructors',
      () {
    for (final currency in FundCurrency.values) {
      for (final other
          in FundCurrency.values.where((value) => value != currency)) {
        expect(
          () => WalletCurrencyRule(
              currency: currency, withdrawFeeCurrency: other),
          throwsFormatException,
        );
        expect(
          () => WalletCurrencyRule.fromJson({'withdrawFeeCurrency': other.code},
              currency: currency),
          throwsFormatException,
        );
      }
    }
    for (final value in ['BTC', '', 'usdt', 0, true]) {
      expect(
        () => WalletCurrencyRule.fromJson({'withdrawFeeCurrency': value},
            currency: FundCurrency.usdt),
        throwsFormatException,
      );
    }
  });

  test('time, cumulative confirmations, memo and account types validate types',
      () {
    for (final field in [
      'estimatedArrivalSeconds',
      'withdrawUnlockConfirmations'
    ]) {
      for (final value in [-1, '1', 1.1, true, '', {}, []]) {
        expect(
          () => WalletCurrencyRule.fromJson({field: value},
              currency: FundCurrency.usdt),
          throwsFormatException,
        );
      }
    }
    for (final value in ['false', 0, 1, {}, []]) {
      expect(
        () => WalletCurrencyRule.fromJson({'memoRequired': value},
            currency: FundCurrency.trx),
        throwsFormatException,
      );
    }
    for (final value in ['', ' wallet', 'wallet ', 0, false]) {
      expect(
        () => WalletCurrencyRule.fromJson({'receivingAccountType': value},
            currency: FundCurrency.trx),
        throwsFormatException,
      );
    }
    expect(
      WalletCurrencyRule.fromJson({'receivingAccountType': 'future-account'},
              currency: FundCurrency.trx)
          .receivingAccountType,
      'future-account',
    );
  });

  test('rules remain immutable metadata and never replace address currencies',
      () {
    final address = WalletDepositAddress.fromJson(_addressJson()
      ..['currencyRules'] = {
        'USDT': {'minDepositAmount': '10'},
        'TRX': {'memoRequired': false},
      });
    expect(address.address, 'unchanged-deposit-address');
    expect(address.currencies, [FundCurrency.trx]);
    expect(address.usdtContract, isEmpty);
    expect(address.confirmations, 19);
    expect(address.ruleFor(FundCurrency.usdt)!.minDepositAmount, '10');
    expect(address.ruleFor(FundCurrency.trx)!.memoRequired, isFalse);
    expect(address.ruleFor(FundCurrency.bi99), isNull);
    expect(() => address.currencyRules.clear(), throwsUnsupportedError);

    final rules = {
      FundCurrency.trx: WalletCurrencyRule(currency: FundCurrency.trx)
    };
    final direct = WalletDepositAddress(
      status: 'ready',
      network: 'TRON',
      address: 'address',
      currencies: const [FundCurrency.trx],
      confirmations: 19,
      usdtContract: '',
      currencyRules: rules,
    );
    rules.clear();
    expect(direct.ruleFor(FundCurrency.trx), isNotNull);
  });

  test('legacy and null rules stay empty while malformed supplied rules fail',
      () {
    expect(
        WalletDepositAddress.fromJson(_addressJson()).currencyRules, isEmpty);
    for (final value in [
      null,
      {},
      {'USDT': null}
    ]) {
      expect(
        WalletDepositAddress.fromJson(_addressJson()..['currencyRules'] = value)
            .currencyRules,
        isEmpty,
      );
    }
    for (final value in [
      [],
      'rules',
      {'BTC': {}},
      {1: {}},
      {'USDT': []},
      {'USDT': 'rule'},
      {
        'USDT': {1: 'invalid key'}
      },
      {
        'USDT': {'withdrawFee': '-1'}
      },
      {
        'USDT': {'withdrawFeeCurrency': 'TRX'}
      },
    ]) {
      expect(
        () => WalletDepositAddress.fromJson(
            _addressJson()..['currencyRules'] = value),
        throwsFormatException,
      );
    }
  });

  test('direct rule maps reject keys that conflict with the rule currency', () {
    expect(
      () => WalletDepositAddress(
        status: 'ready',
        network: 'TRON',
        address: 'address',
        currencies: const [FundCurrency.trx],
        confirmations: 19,
        usdtContract: '',
        currencyRules: {
          FundCurrency.usdt: WalletCurrencyRule(currency: FundCurrency.trx),
        },
      ),
      throwsFormatException,
    );
  });
}
