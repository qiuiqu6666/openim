final _walletRecordAmountPattern =
    RegExp(r'^([+-]?)(\d+|[1-9]\d{0,2}(?:,\d{3})+)(?:\.(\d+))?$');

/// Formats a ledger decimal without converting it through floating point.
/// Rounds half away from zero and retains a supplied sign/thousands format.
/// Unknown or malformed values stay unknown instead of becoming zero.
String walletRecordAmountTwoDecimals(String raw) {
  final match = _walletRecordAmountPattern.firstMatch(raw.trim());
  if (match == null) return '--';

  final sign = match.group(1)!;
  final integer = match.group(2)!;
  final fraction = match.group(3) ?? '';
  final hundred = BigInt.from(100);
  var cents = BigInt.parse(integer.replaceAll(',', '')) * hundred +
      BigInt.parse(fraction.padRight(2, '0').substring(0, 2));
  if (fraction.length > 2 && fraction.codeUnitAt(2) >= 53) {
    cents += BigInt.one;
  }

  var whole = (cents ~/ hundred).toString();
  if (integer.contains(',')) {
    final groups = <String>[];
    for (var end = whole.length; end > 0; end -= 3) {
      final start = end > 3 ? end - 3 : 0;
      groups.add(whole.substring(start, end));
    }
    whole = groups.reversed.join(',');
  }
  final decimals = (cents % hundred).toString().padLeft(2, '0');
  return '$sign$whole.$decimals';
}

/// Formats an original-currency journal decimal without rounding or floats.
/// API amounts have at most six decimals (USDT/TRX) or two (BI99).
/// Removing insignificant zeroes preserves every meaningful decimal place.
String walletRecordAmountExact(String? raw, {bool signed = false}) {
  final match = _walletRecordAmountPattern.firstMatch(raw?.trim() ?? '');
  if (match == null) return '--';
  final integer = BigInt.parse(match.group(2)!.replaceAll(',', '')).toString();
  final fraction = (match.group(3) ?? '').replaceFirst(RegExp(r'0+$'), '');
  final magnitude = fraction.isEmpty ? integer : '$integer.$fraction';
  final zero = integer == '0' && fraction.isEmpty;
  final sign = zero
      ? ''
      : match.group(1) == '-'
          ? '-'
          : signed
              ? '+'
              : '';
  return '$sign$magnitude';
}
