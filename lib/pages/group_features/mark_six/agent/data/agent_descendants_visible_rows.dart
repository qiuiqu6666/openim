// Pure Dart authorized descendant list projection; no SDK or UI dependency.
/// Display the complete, currently authorized data set. A global sort is
/// deliberate: sorting each tree branch separately is not a global ranking.
List<(Map<String, dynamic>, int)> agentVisibleRows(
    List<Map<String, dynamic>> items,
    {required String ownerID,
    String keyword = '',
    String sort = 'balance'}) {
  final byID = {for (final row in items) '${row['userId']}': row};
  final needle = keyword.trim().toLowerCase();
  final filtered = byID.values.where((row) => needle.isEmpty ||
      ['displayName', 'nickname', 'playerNo', 'userId']
          .any((key) => '${row[key] ?? ''}'.toLowerCase().contains(needle)))
      .toList();
  num value(Map<String, dynamic> row) =>
      num.tryParse('${row[sort] ?? ''}') ?? 0;
  filtered.sort((a, b) {
    final rank = value(b).compareTo(value(a));
    if (rank != 0) return rank;
    return '${a['playerNo'] ?? a['userId']}'
        .compareTo('${b['playerNo'] ?? b['userId']}');
  });
  int originalDepth(Map<String, dynamic> row) {
    var depth = 0;
    var parent = '${row['directParentUserId'] ?? ''}';
    final seen = <String>{'${row['userId']}'};
    while (parent.isNotEmpty && parent != ownerID &&
        byID.containsKey(parent) && seen.add(parent) && depth < 4) {
      depth++;
      parent = '${byID[parent]!['directParentUserId'] ?? ''}';
    }
    return depth;
  }
  return filtered.map((row) => (row, originalDepth(row))).toList();
}
