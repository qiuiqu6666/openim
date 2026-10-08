/// Immutable values recorded with the actual wallet posting, never derived from
/// today's user profile or from the displayed ledger page.
class SangongRebateReceipt {
  const SangongRebateReceipt(
      {required this.turnover,
      required this.rate,
      required this.amount,
      required this.claimType,
      required this.accountType,
      required this.turnoverBasis});
  final int? turnover, amount;
  final String rate, claimType, accountType, turnoverBasis;
  bool get automatic => claimType == 'AUTO';
  bool get agent => accountType == 'AGENT_DIFF';
  String get rateLabel {
    if (rate.isEmpty) return '未记录';
    final normalized = rate.contains('.')
        ? rate.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : rate;
    return '$normalized%';
  }

  factory SangongRebateReceipt.fromJson(Map<String, dynamic> json) =>
      SangongRebateReceipt(
          turnover: json['turnover'] is num
              ? (json['turnover'] as num).toInt()
              : int.tryParse('${json['turnover']}'),
          amount: json['amount'] is num
              ? (json['amount'] as num).toInt()
              : int.tryParse('${json['amount']}'),
          rate: json['rate']?.toString() ?? '',
          claimType: json['claimType']?.toString() ?? '',
          accountType: json['accountType']?.toString() ?? '',
          turnoverBasis: json['turnoverBasis']?.toString() ?? '');
}
