// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// Numeric operators may be admin database IDs rather than IM IDs.
Future<Map<String, String>> resolveSangongOperatorNames(
  Iterable<String> operators,
  Future<Map<String, String>> Function(List<String>) fetch, {
  bool Function()? isActive,
}) async {
  final ids = operators
      .map((e) => e.trim())
      .where((id) =>
          RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) &&
          RegExp(r'[a-zA-Z_-]').hasMatch(id))
      .toSet()
      .toList();
  final names = <String, String>{};
  for (var start = 0; start < ids.length; start += 100) {
    if (isActive != null && !isActive()) break;
    final batch =
        ids.sublist(start, start + 100 > ids.length ? ids.length : start + 100);
    try {
      final result = await fetch(batch).timeout(const Duration(seconds: 10));
      for (final id in batch) {
        final name = result[id]?.trim() ?? '';
        if (name.isNotEmpty && name != id) names[id] = name;
      }
    } catch (_) {
      // A name lookup must not hide ledger records or fail the report.
    }
  }
  return names;
}
