import '../../../../services/fund_models.dart';

/// The service must explicitly advertise its accepted currencies. `99` is not
/// silently mapped to the OpenIM wallet's `BI99` or to `PLATFORM`.
class LiveTipCurrency {
  const LiveTipCurrency(this.code, this.label, this.decimals);
  final String code, label;
  final int decimals;
  static List<LiveTipCurrency> fromCapabilities(Map<String, dynamic> map) {
    final raw = map['tipCurrencies'] ?? map['currencies'];
    if (raw is! List) return const [];
    final result = <LiveTipCurrency>[];
    for (final item in raw) {
      final code = item is String
          ? item
          : item is Map
              ? '${item['code'] ?? ''}'
              : '';
      final known = {'USDT': 6, 'TRX': 6, 'BI99': 2, '99': 2}[code];
      final digits =
          item is Map ? item['decimals'] ?? item['scale'] ?? known : known;
      if (code.isEmpty ||
          digits is! int ||
          digits < 0 ||
          digits > 8 ||
          result.any((v) => v.code == code)) {
        continue;
      }
      final label = item is Map
          ? '${item['label'] ?? item['displayName'] ?? code}'
          : code;
      result.add(LiveTipCurrency(code, label, digits));
    }
    return List.unmodifiable(result);
  }

  int units(String text) {
    BigInt value;
    final existing = FundCurrency.values.where(
        (currency) => currency.code == code && currency.decimals == decimals);
    if (existing.isNotEmpty) {
      value = FundAmount.parse(text, existing.first).units;
    } else {
      final input = text.trim();
      if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(input)) {
        throw const FormatException('请输入有效金额');
      }
      final parts = input.split('.');
      final fraction = parts.length == 2 ? parts[1] : '';
      if (fraction.length > decimals) {
        throw FormatException('$label 最多支持 $decimals 位小数');
      }
      value = BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
          BigInt.parse(fraction.padRight(decimals, '0').isEmpty
              ? '0'
              : fraction.padRight(decimals, '0'));
    }
    if (value <= BigInt.zero || value > BigInt.from(9007199254740991)) {
      throw const FormatException('金额超出可支付范围');
    }
    return value.toInt();
  }
}
