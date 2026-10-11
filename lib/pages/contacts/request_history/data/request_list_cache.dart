import 'dart:convert';

import 'request_history_store.dart';

/// Small presentation snapshots, never used as authoritative SDK paging state.
class RequestListCache {
  RequestListCache({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  static final shared = RequestListCache();
  static const lifetime = Duration(seconds: 30);
  static const limit = 100;
  (String, String?)? _session;
  final _snapshots = <RequestHistoryKind, (DateTime, String)>{};

  void clear() {
    _session = null;
    _snapshots.clear();
  }

  void _bind(String account, String? token) {
    if (_session != (account, token)) {
      clear();
      _session = (account, token);
    }
  }

  List<T> read<T>(String account, String? token, RequestHistoryKind kind,
      T Function(Map<String, dynamic>) decode) {
    _bind(account, token);
    final snapshot = _snapshots[kind];
    if (account.isEmpty || snapshot == null) return [];
    if (_now().difference(snapshot.$1) >= lifetime) {
      _snapshots.remove(kind);
      return [];
    }
    return (jsonDecode(snapshot.$2) as List)
        .map((row) => decode(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  void save(String account, String? token, RequestHistoryKind kind,
      Iterable<Map<String, dynamic>> rows) {
    if (account.isEmpty) return;
    _bind(account, token);
    _snapshots[kind] = (_now(), jsonEncode(rows.take(limit).toList()));
  }
}
