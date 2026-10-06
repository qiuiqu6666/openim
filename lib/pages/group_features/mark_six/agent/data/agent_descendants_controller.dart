// Scoped pagination adapted from 99chat agent_rebate_descendants_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/mark_six_repository.dart';
import '../../models/mark_six_json.dart';

class AgentDescendantsController extends ChangeNotifier {
  AgentDescendantsController(this.repository) {
    _events = repository.context.events.listen((event) {
      if (_disposed ||
          repository.privateCurrent ||
          '${event['groupID'] ?? ''}' != repository.context.groupID) {
        return;
      }
      _generation++;
      items = [];
      total = 0;
      page = 0;
      hasMore = false;
      loading = false;
      _work = null;
      notifyListeners();
    });
  }
  final MarkSixRepository repository;
  List<Map<String, dynamic>> items = [];
  String scope = 'all';
  int page = 0, total = 0;
  bool hasMore = false, loading = false;
  String? error;
  String ownerID = '';
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _work;
  StreamSubscription<Map<String, dynamic>>? _events;
  bool get current => !_disposed && repository.privateCurrent;
  Future<void> selectScope(String next) {
    if (!['all', 'direct'].contains(next) || next == scope) {
      return Future.value();
    }
    scope = next;
    _generation++;
    _work = null;
    loading = false;
    items = [];
    page = 0;
    hasMore = false;
    return load();
  }

  Future<void> load({bool more = false, bool force = false}) {
    if (!current || (more && !hasMore)) return Future.value();
    if (_work != null) return _work!;
    final generation = ++_generation;
    final requestedPage = more ? page + 1 : 1;
    loading = true;
    error = null;
    notifyListeners();
    late final Future<void> work;
    work = repository
        .read('/me/agent/descendants',
            query: {'scope': scope, 'page': requestedPage, 'pageSize': 100},
            force: force)
        .then((response) {
      if (!current || generation != _generation) return;
      final data = MarkSixRepository.payload(response);
      if (data['page'] != null && data['page'] != requestedPage) {
        throw const FormatException('下级分页上下文错误');
      }
      final rows = markSixRows(data);
      if (rows.any((row) => '${row['userId'] ?? ''}'.trim().isEmpty)) {
        throw const FormatException('下级用户编号缺失');
      }
      if (data['hasMore'] == true && rows.isEmpty) {
        throw const FormatException('下级分页未前进');
      }
      final byID = <String, Map<String, dynamic>>{};
      for (final row in [
        ...(more ? items : <Map<String, dynamic>>[]),
        ...rows
      ]) {
        byID['${row['userId']}'] = row;
      }
      items = byID.values.toList();
      page = requestedPage;
      total = (data['total'] as num?)?.toInt() ?? items.length;
      ownerID = '${data['userId'] ?? ''}';
      hasMore = data['hasMore'] == true;
    }).catchError((Object failure) {
      if (current && generation == _generation) error = failure.toString();
    }).whenComplete(() {
      if (current && generation == _generation) {
        loading = false;
        notifyListeners();
      }
      if (identical(_work, work)) _work = null;
    });
    _work = work;
    return work;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _events?.cancel();
    super.dispose();
  }
}

/// Retains orphaned/missing-parent rows and terminates cycles without hiding data.
List<(Map<String, dynamic>, int)> agentVisibleRows(
    List<Map<String, dynamic>> items,
    {required String ownerID,
    String keyword = '',
    String sort = 'balance'}) {
  final byID = {for (final row in items) '${row['userId']}': row};
  final children = <String, List<Map<String, dynamic>>>{};
  final roots = <Map<String, dynamic>>[];
  for (final row in byID.values) {
    final parent = '${row['directParentUserId'] ?? ''}';
    if (parent.isEmpty ||
        parent == ownerID ||
        parent == '${row['userId']}' ||
        !byID.containsKey(parent)) {
      roots.add(row);
    } else {
      (children[parent] ??= []).add(row);
    }
  }
  int compare(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (num.tryParse('${b[sort]}') ?? 0)
          .compareTo(num.tryParse('${a[sort]}') ?? 0);
  roots.sort(compare);
  for (final rows in children.values) {
    rows.sort(compare);
  }
  final seen = <String>{};
  final result = <(Map<String, dynamic>, int)>[];
  final needle = keyword.trim().toLowerCase();
  void visit(Map<String, dynamic> row, int depth) {
    final id = '${row['userId']}';
    if (!seen.add(id)) return;
    if (needle.isEmpty ||
        ['displayName', 'nickname', 'playerNo', 'userId']
            .any((key) => '${row[key] ?? ''}'.toLowerCase().contains(needle))) {
      result.add((row, depth));
    }
    for (final child in children[id] ?? <Map<String, dynamic>>[]) {
      visit(child, (depth + 1).clamp(0, 8));
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  for (final row in byID.values) {
    visit(row, 0);
  }
  return result;
}
