// Presentation-only descendant hierarchy.  The C# business relationship and
// complete /me/agent/descendants snapshot remain the source of truth.
// The default tree order follows 99CHAT; ranking/search use the full snapshot.

enum AgentDescendantView { team, ranking }

typedef AgentDescendantVisibleRow = (Map<String, dynamic>, int);

class AgentDescendantsProjection {
  AgentDescendantsProjection(
    List<Map<String, dynamic>> items, {
    required this.ownerID,
  }) {
    for (final item in items) {
      final id = _field(item, 'userId').trim();
      if (id.isEmpty) continue;
      // The server normally deduplicates. Keep one row per user if a caller
      // passes duplicate records, without changing the original userId.
      byID.putIfAbsent(id, () => item);
    }
    for (final entry in byID.entries) {
      final id = entry.key;
      final parent = _field(entry.value, 'directParentUserId').trim();
      if (parent.isEmpty || parent == ownerID || parent == id ||
          !byID.containsKey(parent)) {
        roots.add(entry.value);
      } else {
        childrenByParent.putIfAbsent(parent, () => []).add(entry.value);
      }
    }
  }

  final String ownerID;
  final Map<String, Map<String, dynamic>> byID = {};
  final Map<String, List<Map<String, dynamic>>> childrenByParent = {};
  final List<Map<String, dynamic>> roots = [];

  static String _field(Map<String, dynamic> item, String key) =>
      '${item[key] ?? ''}';

  static String label(Map<String, dynamic> item) {
    final name = _field(item, 'displayName').trim();
    final nickname = _field(item, 'nickname').trim();
    final no = _field(item, 'playerNo').trim();
    return name.isNotEmpty ? name : nickname.isNotEmpty ? nickname :
        no.isNotEmpty ? no : _field(item, 'userId');
  }

  static String namedNumber(Map<String, dynamic> item) {
    final no = _field(item, 'playerNo').trim();
    final name = label(item);
    return no.isNotEmpty && no != name ? '$name（$no）' : name;
  }

  String parentDescription(Map<String, dynamic> item) {
    final id = _field(item, 'userId').trim();
    final parent = _field(item, 'directParentUserId').trim();
    if (parent.isEmpty || parent == id) return '直属上级：关系待确认';
    if (ownerID.isNotEmpty && parent == ownerID) return '直属上级：当前代理';
    final found = byID[parent];
    if (found != null) return '直属上级：${namedNumber(found)}';
    final parentNo = _field(item, 'directParentNo').trim();
    return parentNo.isNotEmpty
        ? '直属上级编号：$parentNo（未收录）'
        : '直属上级：未收录的上级';
  }

  /// Only follows verified IDs supplied by C#. Never infers relationships from
  /// similar nicknames. A broken path is marked instead of invented.
  String relationshipPath(Map<String, dynamic> item) {
    final path = <String>[];
    final seen = <String>{};
    var current = item;
    while (true) {
      final id = _field(current, 'userId').trim();
      if (id.isEmpty || !seen.add(id)) {
        path.add('关系异常');
        break;
      }
      path.add(namedNumber(current));
      final parent = _field(current, 'directParentUserId').trim();
      if (parent.isEmpty) break;
      if (parent == ownerID && ownerID.isNotEmpty) {
        path.add('当前代理');
        break;
      }
      final next = byID[parent];
      if (next == null) {
        final no = _field(current, 'directParentNo').trim();
        path.add(no.isEmpty ? '上级未收录' : '上级编号 $no（未收录）');
        break;
      }
      current = next;
    }
    return '所属关系：${path.reversed.join(' → ')}';
  }

  List<AgentDescendantVisibleRow> visibleRows({
    AgentDescendantView view = AgentDescendantView.team,
    String keyword = '',
    String sort = 'balance',
    bool descending = true,
  }) {
    final needle = keyword.trim().toLowerCase();
    bool matches(Map<String, dynamic> row) =>
        ['displayName', 'nickname', 'playerNo', 'userId']
            .any((key) => _field(row, key).toLowerCase().contains(needle));
    num value(Map<String, dynamic> row) =>
        num.tryParse(_field(row, sort)) ?? 0;
    int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
      final result = value(a).compareTo(value(b));
      if (result != 0) return descending ? -result : result;
      final name = label(a).compareTo(label(b));
      if (name != 0) return name;
      return _field(a, 'userId').compareTo(_field(b, 'userId'));
    }

    // Searching finds just the matching players (not their whole team), with a
    // separate, exact parent path displayed on their card. Ranking is global.
    if (needle.isNotEmpty || view == AgentDescendantView.ranking) {
      final matched = byID.values.where((r) => needle.isEmpty || matches(r))
          .toList()..sort(compare);
      return [for (final item in matched) (item, 0)];
    }

    // Preserve the 99CHAT grouping rule: sort first-level roots by their OWN
    // metric; then render each branch consecutively in existing source order.
    final sortedRoots = roots.toList()..sort(compare);
    final output = <AgentDescendantVisibleRow>[];
    final visited = <String>{};
    void appendBranch(Map<String, dynamic> root) {
      final stack = <AgentDescendantVisibleRow>[(root, 0)];
      while (stack.isNotEmpty) {
        final (item, depth) = stack.removeLast();
        final id = _field(item, 'userId').trim();
        if (!visited.add(id)) continue; // also cuts bad parent cycles
        output.add((item, depth));
        final children = childrenByParent[id];
        if (children == null) continue;
        for (var index = children.length - 1; index >= 0; index--) {
          stack.add((children[index], depth + 1));
        }
      }
    }
    for (final root in sortedRoots) {
      appendBranch(root);
    }
    // A closed parent cycle has no root. Include it once rather than silently
    // dropping players. The source relationship is never rewritten.
    for (final item in byID.values) {
      if (!visited.contains(_field(item, 'userId').trim())) {
        appendBranch(item);
      }
    }
    return output;
  }
}

/// Kept for existing callers and tests. The default now matches 99CHAT's
/// first-level grouping rather than flattening every player into one ranking.
List<AgentDescendantVisibleRow> agentVisibleRows(
  List<Map<String, dynamic>> items, {
  required String ownerID,
  String keyword = '',
  String sort = 'balance',
  bool descending = true,
  AgentDescendantView view = AgentDescendantView.team,
}) => AgentDescendantsProjection(items, ownerID: ownerID).visibleRows(
      view: view, keyword: keyword, sort: sort, descending: descending);
