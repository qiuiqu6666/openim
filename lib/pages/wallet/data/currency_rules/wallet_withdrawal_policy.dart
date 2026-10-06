import '../../../../services/fund_models.dart';
import 'wallet_currency_rule.dart';

enum WalletWithdrawalPolicyIssue {
  incomplete,
  belowMinimum,
  insufficientBalance
}

/// Exact withdrawal arithmetic. The fee is added to the transferred principal.
class WalletWithdrawalPolicy {
  const WalletWithdrawalPolicy({required this.rule});
  final WalletCurrencyRule rule;

  WalletWithdrawalPolicyIssue? validate({
    required FundAmount amount,
    required FundAmount available,
  }) {
    if (!rule.isWithdrawalComplete ||
        amount.currency != rule.currency ||
        available.currency != rule.currency) {
      return WalletWithdrawalPolicyIssue.incomplete;
    }
    final minimum = FundAmount.parse(rule.minWithdrawAmount!, rule.currency);
    if (!amount.isPositive || amount.compareTo(minimum) < 0) {
      return WalletWithdrawalPolicyIssue.belowMinimum;
    }
    if (totalDebit(amount).compareTo(available) > 0) {
      return WalletWithdrawalPolicyIssue.insufficientBalance;
    }
    return null;
  }

  FundAmount totalDebit(FundAmount amount) {
    _requireComplete(amount.currency);
    return addFee(amount, FundAmount.parse(rule.withdrawFee!, rule.currency));
  }

  /// The maximum principal which leaves enough available funds for the fee.
  FundAmount spendable(FundAmount available) {
    _requireComplete(available.currency);
    final units = available.units -
        FundAmount.parse(rule.withdrawFee!, rule.currency).units;
    return _fromUnits(units < BigInt.zero ? BigInt.zero : units, rule.currency);
  }

  static FundAmount addFee(FundAmount amount, FundAmount fee) {
    if (amount.currency != fee.currency) {
      throw ArgumentError('Withdrawal fee currency does not match');
    }
    return _fromUnits(amount.units + fee.units, amount.currency);
  }

  void _requireComplete(FundCurrency currency) {
    if (!rule.isWithdrawalComplete || currency != rule.currency) {
      throw const FormatException('Incomplete withdrawal rules');
    }
  }

  static FundAmount _fromUnits(BigInt units, FundCurrency currency) {
    if (units < BigInt.zero) throw ArgumentError('Negative spending amount');
    final scale = BigInt.from(10).pow(currency.decimals);
    final whole = units ~/ scale;
    final fraction = (units % scale).toString().padLeft(currency.decimals, '0');
    return FundAmount.parse('$whole.$fraction', currency);
  }
}
