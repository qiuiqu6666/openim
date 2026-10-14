// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.

/// Shared by long-press quick setup and the member profile's banker controls.
class SangongBankerSetupParseResult {
  const SangongBankerSetupParseResult(
      {this.door, this.limit, this.hasExplicitLimit = false});
  final int? door, limit;
  final bool hasExplicitLimit;
}

SangongBankerSetupParseResult parseSangongBankerSetupText(String text) {
  // Normalize full-width ASCII from Chinese keyboards, retaining token spaces.
  final input = String.fromCharCodes(
          text.runes.map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r))
      .trim();
  final pair =
      _bankerParentheses.firstMatch(input) ?? _bankerPair.firstMatch(input);
  if (pair != null) {
    final door = int.tryParse(pair.group(1)!);
    final limit = _parseLimit(pair.group(2)!, pair.group(3)!);
    if (door == null || limit == null) {
      return const SangongBankerSetupParseResult();
    }
    return SangongBankerSetupParseResult(
        door: door, limit: limit, hasExplicitLimit: true);
  }
  final single = _bankerDoor.firstMatch(input);
  return SangongBankerSetupParseResult(
      door: single == null ? null : int.tryParse(single.group(1)!));
}

final _bankerDoor = RegExp(r'^(?:庄\s*)?([+-]?\d+)\s*(?:门)?$');
// One symbol only; escaping each literal keeps regex punctuation literal.
const _bankerSeparators =
    '''。. ,，/、+:：;；()!！?？"'‘’“”#\$%&*<=>@[]^_`{|}~×÷±≈≠≤≥∞∑√…·ˉ∶〃-\\''';
final _bankerSymbol = _bankerSeparators
    .replaceAll(' ', '')
    .split('')
    .map(RegExp.escape)
    .join('|');
const _bankerAmount = r'(-?\d+(?:\.\d+)?)\s*([百千万kKwW]?)';
final _bankerPair =
    RegExp(r'^(?:庄\s*)?([+-]?\d+)(?:\s*(?:门\s*(?:限(?:额)?)?|限(?:额)?|'
        '$_bankerSymbol'
        r')\s*|\s+)'
        '$_bankerAmount'
        r'$');
final _bankerParentheses = RegExp(r'^(?:庄\s*)?([+-]?\d+)\s*\(\s*'
    '$_bankerAmount'
    r'\s*\)$');

int? _parseLimit(String amount, String unit) {
  // Decimal amounts require a unit: 2.5千 means door 2, limit 5,000;
  // 2*2.5千 means door 2, limit 2,500. Never round fractional limits.
  final parts = amount.split('.');
  if (parts.length > 1 && unit.isEmpty) return null;
  final multiplier = switch (unit.toLowerCase()) {
    '百' => 100,
    '千' || 'k' => 1000,
    '万' || 'w' => 10000,
    _ => 1,
  };
  final digits = BigInt.tryParse(parts.join());
  if (digits == null) return null;
  final numerator = digits * BigInt.from(multiplier);
  final denominator =
      BigInt.from(10).pow(parts.length > 1 ? parts[1].length : 0);
  if (numerator.remainder(denominator) != BigInt.zero) return null;
  final value = numerator ~/ denominator;
  // Keep JSON integer values exact across native and web clients.
  if (value.abs() > BigInt.from(9007199254740991)) return null;
  return value.toInt();
}
