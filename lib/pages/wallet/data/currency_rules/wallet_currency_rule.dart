import '../../../../services/fund_models.dart';

/// Optional server rules retain unknown values and exact monetary strings.
class WalletCurrencyRule {
  factory WalletCurrencyRule({
    required FundCurrency currency,
    String? minDepositAmount,
    String? minWithdrawAmount,
    String? withdrawFee,
    FundCurrency? withdrawFeeCurrency,
    String? receivingAccountType,
    int? estimatedArrivalSeconds,
    int? withdrawUnlockConfirmations,
    bool? memoRequired,
  }) {
    if (withdrawFeeCurrency != null && withdrawFeeCurrency != currency) {
      throw const FormatException(
          'Withdrawal fee currency does not match rule');
    }
    return WalletCurrencyRule._(
      currency: currency,
      minDepositAmount: _decimal(minDepositAmount, currency),
      minWithdrawAmount: _decimal(minWithdrawAmount, currency),
      withdrawFee: _decimal(withdrawFee, currency),
      withdrawFeeCurrency: withdrawFeeCurrency,
      receivingAccountType: _accountType(receivingAccountType),
      estimatedArrivalSeconds: _nonNegativeInteger(
          estimatedArrivalSeconds, 'estimatedArrivalSeconds'),
      withdrawUnlockConfirmations: _nonNegativeInteger(
          withdrawUnlockConfirmations, 'withdrawUnlockConfirmations'),
      memoRequired: memoRequired,
    );
  }

  const WalletCurrencyRule._({
    required this.currency,
    required this.minDepositAmount,
    required this.minWithdrawAmount,
    required this.withdrawFee,
    required this.withdrawFeeCurrency,
    required this.receivingAccountType,
    required this.estimatedArrivalSeconds,
    required this.withdrawUnlockConfirmations,
    required this.memoRequired,
  });

  factory WalletCurrencyRule.fromJson(Map<String, dynamic> json,
          {required FundCurrency currency}) =>
      WalletCurrencyRule(
        currency: currency,
        minDepositAmount: _nullableString(json, 'minDepositAmount'),
        minWithdrawAmount: _nullableString(json, 'minWithdrawAmount'),
        withdrawFee: _nullableString(json, 'withdrawFee'),
        withdrawFeeCurrency: json['withdrawFeeCurrency'] == null
            ? null
            : FundCurrency.parse(_nullableString(json, 'withdrawFeeCurrency')!),
        receivingAccountType: _nullableString(json, 'receivingAccountType'),
        estimatedArrivalSeconds: _nonNegativeInteger(
            json['estimatedArrivalSeconds'], 'estimatedArrivalSeconds'),
        withdrawUnlockConfirmations: _nonNegativeInteger(
            json['withdrawUnlockConfirmations'], 'withdrawUnlockConfirmations'),
        memoRequired: _nullableBool(json['memoRequired'], 'memoRequired'),
      );

  final FundCurrency currency;
  final String? minDepositAmount;
  final String? minWithdrawAmount;
  final String? withdrawFee;
  final FundCurrency? withdrawFeeCurrency;
  final String? receivingAccountType;
  final int? estimatedArrivalSeconds;

  /// Cumulative confirmation threshold required before withdrawals unlock.
  final int? withdrawUnlockConfirmations;
  final bool? memoRequired;

  bool get isWithdrawalComplete =>
      minWithdrawAmount != null &&
      withdrawFee != null &&
      withdrawFeeCurrency == currency;
}

String? _decimal(String? value, FundCurrency currency) {
  if (value == null) return null;
  final match = RegExp(r'\d+(?:\.\d+)?').matchAsPrefix(value);
  if (match == null || match.end != value.length) {
    throw const FormatException('Rule amounts must be nonnegative decimals');
  }
  FundAmount.parse(value, currency);
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid rule $key');
  return value;
}

String? _accountType(String? value) {
  if (value == null) return null;
  if (value.isEmpty || value != value.trim()) {
    throw const FormatException('Invalid receiving account type');
  }
  return value;
}

int? _nonNegativeInteger(dynamic value, String key) {
  if (value == null) return null;
  if (value is! int || value < 0) throw FormatException('Invalid rule $key');
  return value;
}

bool? _nullableBool(dynamic value, String key) {
  if (value == null) return null;
  if (value is! bool) throw FormatException('Invalid rule $key');
  return value;
}
