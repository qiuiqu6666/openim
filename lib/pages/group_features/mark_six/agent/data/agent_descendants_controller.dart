// Scoped descendant snapshot for the current agent and group.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/mark_six_repository.dart';
import '../../models/mark_six_json.dart';
export 'agent_descendants_visible_rows.dart';

class AgentDescendantsController extends ChangeNotifier {
  AgentDescendantsController(this.repository) {
    _events = repository.context.events.listen((event) {
      if (_disposed || repository.privateCurrent ||
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
    total = 0;
    hasMore = false;
    return load();
  }

  /// Pre-C# upgrade compatibility: this endpoint returns the complete authorized
  /// descendant set if page/pageSize are omitted. Always use a single snapshot
  /// so local search, ranking and detail links see the same population.
  Future<void> load({bool more = false, bool force = false}) {
    if (!current) return Future.value();
    if (more) return Future.value();
    if (_work != null) return _work!;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    late final Future<void> work;
    work = repository
        .read('/me/agent/descendants', query: {'scope': scope}, force: force)
        .then((response) {
      if (!current || generation != _generation) return;
      final data = MarkSixRepository.payload(response);
      final rows = markSixRows(data);
      if (rows.any((row) => '${row['userId'] ?? ''}'.trim().isEmpty)) {
        throw const FormatException('下级用户编号缺失');
      }
      final reportedTotal = (data['total'] as num?)?.toInt();
      if (reportedTotal != null && reportedTotal != rows.length) {
        throw FormatException('下级名单不完整：${rows.length} / $reportedTotal');
      }
      final byID = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        byID['${row['userId']}'] = row;
      }
      items = byID.values.toList();
      page = 1;
      total = reportedTotal ?? items.length;
      ownerID = '${data['userId'] ?? ''}';
      hasMore = false;
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
