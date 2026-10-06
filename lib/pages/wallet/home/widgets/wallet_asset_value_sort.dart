import '../../wallet_repository.dart';

/// Compare valuation strings exactly, retaining source order for equal values.
List<CoinDto> sortWalletAssetsByValue(List<CoinDto> source,
    {required bool descending}) {
  BigInt? cents(CoinDto coin) {
    final raw = coin.fiat.replaceAll(RegExp(r'[¥￥$,\s≈]'), '');
    if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(raw)) return null;
    final negative = raw.startsWith('-');
    final parts = raw.replaceFirst('-', '').split('.');
    final value = BigInt.parse(parts.first) * BigInt.from(100) +
        BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    return negative ? -value : value;
  }

  final indexed = source.asMap().entries.toList();
  indexed.sort((a, b) {
    final av = cents(a.value), bv = cents(b.value);
    if (av == null && bv != null) return 1;
    if (av != null && bv == null) return -1;
    final order = av == null ? 0 : av.compareTo(bv!);
    return order == 0
        ? a.key.compareTo(b.key)
        : descending
            ? -order
            : order;
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}
