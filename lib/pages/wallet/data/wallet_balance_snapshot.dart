import '../../../services/fund_models.dart';
import '../record/wallet_record_amount.dart';

/// Balances and their valuation rate belong to the same API response.
class WalletBalanceSnapshot {
  const WalletBalanceSnapshot({
    required this.balances,
    this.totalCny = "--",
    this.dailyAmountCny = "--",
    this.dailyPercentage = "--",
    this.valuesCny = const {},
    this.changesCny = const {},
    this.changePercentages = const {},
    this.usdToThisRate,
    this.usdToThisRateUpdatedAt,
  });

  final List<FundBalance> balances;
  final String totalCny;
  final String dailyAmountCny;
  final String dailyPercentage;
  final Map<FundCurrency, String> valuesCny;
  final Map<FundCurrency, String> changesCny;
  final Map<FundCurrency, String> changePercentages;
  final num? usdToThisRate;
  final int? usdToThisRateUpdatedAt;

  /// Only USDT is priced by this endpoint; frozen funds are not spendable.
  String get usdtCnyValue {
    final rate = usdToThisRate;
    if (rate == null || !rate.isFinite || rate <= 0) return '--';
    final usdt = balances.where((b) => b.currency == FundCurrency.usdt);
    if (usdt.isEmpty) return '--';
    // Convert the supplied decimal rate into integer units, including exponent
    // notation. Multiply before rounding so large balances retain precision.
    final parts = rate.toString().toLowerCase().split('e');
    final decimal = parts.first.split('.');
    final fraction = decimal.length > 1 ? decimal[1] : '';
    final exponent = parts.length > 1 ? int.parse(parts[1]) : 0;
    final coefficient = BigInt.parse('${decimal.first}$fraction');
    final scale = FundCurrency.usdt.decimals + fraction.length - exponent;
    var product = usdt.first.available.units * coefficient;
    if (scale <= 0) {
      product *= BigInt.from(10).pow(-scale);
      return walletRecordAmountTwoDecimals(product.toString());
    }
    final digits = product.abs().toString().padLeft(scale + 1, '0');
    final split = digits.length - scale;
    return walletRecordAmountTwoDecimals(
        '${product.isNegative ? '-' : ''}${digits.substring(0, split)}.${digits.substring(split)}');
  }
}

/// Validate server decimal text without floating point conversion.
String walletServerDecimal(dynamic value) {
  if (value is! String || !RegExp(r"^[+-]?\d+(?:\.\d+)?$").hasMatch(value))
    return "--";
  return walletRecordAmountTwoDecimals(value);
}
