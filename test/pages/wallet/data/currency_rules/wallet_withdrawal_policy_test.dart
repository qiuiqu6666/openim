import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/currency_rules/wallet_withdrawal_policy.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';

void main() {
  WalletWithdrawalPolicy policy(
          {String minimum = '10', String fee = '0.000001'}) =>
      WalletWithdrawalPolicy(
          rule: WalletCurrencyRule(
        currency: FundCurrency.usdt,
        minWithdrawAmount: minimum,
        withdrawFee: fee,
        withdrawFeeCurrency: FundCurrency.usdt,
      ));
  FundAmount amount(String value) => FundAmount.parse(value, FundCurrency.usdt);

  test('minimum excludes fee; the available balance must cover both exactly',
      () {
    final value = policy();
    expect(value.validate(amount: amount('9.999999'), available: amount('100')),
        WalletWithdrawalPolicyIssue.belowMinimum);
    expect(value.validate(amount: amount('10'), available: amount('10')),
        WalletWithdrawalPolicyIssue.insufficientBalance);
    expect(value.validate(amount: amount('10'), available: amount('10.000001')),
        isNull);
    expect(value.totalDebit(amount('10')).decimal, '10.000001');
    expect(value.spendable(amount('10.000001')).decimal, '10');
    expect(value.spendable(amount('0')).decimal, '0');
  });

  test('large amounts retain one smallest unit beyond double precision', () {
    final value = policy(minimum: '0');
    final principal = amount('9007199254.740991');
    expect(value.totalDebit(principal).units, BigInt.parse('9007199254740992'));
    expect(value.validate(amount: principal, available: principal),
        WalletWithdrawalPolicyIssue.insufficientBalance);
    expect(value.spendable(amount('9007199254.740992')), principal);
  });

  test('explicit zero fee is valid; missing fee is incomplete', () {
    final noFee = policy(minimum: '0', fee: '0');
    expect(
        noFee.validate(
            amount: amount('0.000001'), available: amount('0.000001')),
        isNull);
    final unknown = WalletWithdrawalPolicy(
        rule: WalletCurrencyRule(
            currency: FundCurrency.usdt, minWithdrawAmount: '0'));
    expect(unknown.validate(amount: amount('1'), available: amount('100')),
        WalletWithdrawalPolicyIssue.incomplete);
    expect(() => unknown.totalDebit(amount('1')), throwsFormatException);
  });

  test('receipt addition refuses a different fee currency', () {
    expect(
        () => WalletWithdrawalPolicy.addFee(
            amount('10'), FundAmount.parse('1', FundCurrency.trx)),
        throwsArgumentError);
  });
}
