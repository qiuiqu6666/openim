// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.

/// The reference profile accepts a door, or a door followed by a display limit.
class SangongBankerSetupParseResult {
  const SangongBankerSetupParseResult(
      {this.door, this.limit, this.hasExplicitLimit = false});
  final int? door, limit;
  final bool hasExplicitLimit;
}

SangongBankerSetupParseResult parseSangongBankerSetupText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const SangongBankerSetupParseResult();
  for (final separator in ['.', '/', '、', '-', '+']) {
    final index = trimmed.indexOf(separator);
    if (index <= 0 || index >= trimmed.length - 1) continue;
    final door = int.tryParse(trimmed.substring(0, index).trim());
    final limit = int.tryParse(trimmed.substring(index + 1).trim());
    if (door != null && limit != null) {
      return SangongBankerSetupParseResult(
          door: door, limit: limit, hasExplicitLimit: true);
    }
  }
  return SangongBankerSetupParseResult(door: int.tryParse(trimmed));
}
