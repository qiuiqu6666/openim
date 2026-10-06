import '../../../../services/fund_models.dart';

/// A server quote locks the exact input and the received accounting units.
/// Prices are validated with integers, including the server's 18-place rate.
class WalletSwapQuote {
  const WalletSwapQuote({
    required this.quoteID,
    required this.amount,
    required this.toCurrency,
    required this.estimatedReceived,
    required this.rate,
    required this.marketRate,
    required this.adjustmentPercent,
    required this.inputValueUsd,
    required this.expiresAt,
  });

  factory WalletSwapQuote.fromJson(Map<String, dynamic> json) {
    final from = FundCurrency.parse(_string(json, 'fromCurrency'));
    final to = FundCurrency.parse(_string(json, 'toCurrency'));
    if (from == to) throw const FormatException('Invalid swap quote pair');
    final amount = _amount(json['amount'], from);
    final received = _amount(json['estimatedReceived'], to);
    final rate = _rate(json['rate']);
    final marketRate = _rate(json['marketRate']);
    final adjustment = _adjustment(json['adjustmentPercent']);
    final rawUsd = json['inputValueUsd'];
    if (rawUsd != null &&
        (rawUsd is! String || !RegExp(r'^\d+\.\d{2}$').hasMatch(rawUsd))) {
      throw const FormatException('Invalid swap quote USD value');
    }
    // floor(input accounting units * saved rate * target scale / input scale).
    final expectedUnits = amount.units *
        BigInt.parse(rate.replaceAll('.', '')) *
        BigInt.from(10).pow(to.decimals) ~/
        BigInt.from(10).pow(from.decimals + 18);
    if (received.units != expectedUnits) {
      throw const FormatException('Swap quote received amount does not match');
    }
    final rawExpiry = json['expiresAt'];
    if (rawExpiry is! int || rawExpiry <= 0) {
      throw const FormatException('Invalid swap quote expiry');
    }
    DateTime expiry;
    try {
      expiry = DateTime.fromMillisecondsSinceEpoch(rawExpiry, isUtc: true);
    } on ArgumentError {
      throw const FormatException('Invalid swap quote expiry');
    }
    return WalletSwapQuote(
      quoteID: _string(json, 'quoteID'),
      amount: amount,
      toCurrency: to,
      estimatedReceived: received,
      rate: rate,
      marketRate: marketRate,
      adjustmentPercent: adjustment,
      inputValueUsd: rawUsd as String?,
      expiresAt: expiry,
    );
  }

  final String quoteID;
  final FundAmount amount;
  FundCurrency get fromCurrency => amount.currency;
  final FundCurrency toCurrency;
  final FundAmount estimatedReceived;
  final String rate;
  final String marketRate;
  final String adjustmentPercent;
  final String? inputValueUsd;
  final DateTime expiresAt;

  bool matches(FundAmount input, FundCurrency target) =>
      amount == input && toCurrency == target;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty || RegExp(r'\s').hasMatch(value)) {
      throw FormatException('Invalid swap quote $key');
    }
    return value;
  }

  static FundAmount _amount(dynamic raw, FundCurrency currency) {
    if (raw is! String || !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(raw)) {
      throw const FormatException('Invalid swap quote amount');
    }
    final amount = FundAmount.parse(raw, currency);
    if (!amount.isPositive) {
      throw const FormatException('Invalid positive swap quote amount');
    }
    return amount;
  }

  static String _rate(dynamic raw) {
    if (raw is! String || !RegExp(r'^\d+\.\d{18}$').hasMatch(raw)) {
      throw const FormatException('Invalid swap quote rate');
    }
    if (BigInt.parse(raw.replaceAll('.', '')) <= BigInt.zero) {
      throw const FormatException('Invalid positive swap quote rate');
    }
    return raw;
  }

  static String _adjustment(dynamic raw) {
    if (raw is! String || !RegExp(r'^-?\d+(?:\.\d{1,6})?$').hasMatch(raw)) {
      throw const FormatException('Invalid swap quote adjustment');
    }
    final negative = raw.startsWith('-');
    final parts = (negative ? raw.substring(1) : raw).split('.');
    final units = BigInt.parse(parts.first) * BigInt.from(1000000) +
        BigInt.parse((parts.length > 1 ? parts[1] : '').padRight(6, '0'));
    final signed = negative ? -units : units;
    if (signed < BigInt.from(-99000000) || signed > BigInt.from(100000000)) {
      throw const FormatException('Swap quote adjustment outside range');
    }
    return raw;
  }
}
