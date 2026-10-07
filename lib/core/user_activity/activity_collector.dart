import 'dart:async';

import 'activity_schema.dart';

typedef ActivitySession = ({String accountID, String token, String endpoint});
typedef ActivityUpload = Future<bool> Function(
    ActivitySession owner, Map<String, Object> batch);

/// Bounded, memory-only analytics. Never retries a business operation.
class ActivityCollector {
  ActivityCollector(
      {required this.upload, required this.newID, DateTime Function()? now})
      : now = now ?? DateTime.now;

  final ActivityUpload upload;
  final String Function() newID;
  final DateTime Function() now;
  ActivitySession? _owner;
  String? _sessionID;
  String _page = 'home';
  int _seq = 0, _generation = 0, _failures = 0;
  bool _foreground = true, _sending = false;
  DateTime? _lastInput, _lastHeartbeat, _retryAt, _started;
  final List<Map<String, Object>> _queue = [];
  String? get sessionID => _sessionID;
  ActivitySession? get owner => _owner;
  int get pendingCount => _queue.length;
  String get page => _page;

  void bind(ActivitySession? owner) {
    if (_owner == owner) return;
    invalidate();
    _owner = owner;
    if (owner != null) _start();
  }

  void _start({bool continuation = false}) {
    _sessionID = newID();
    _started = now();
    _seq = 0;
    _lastInput = null;
    _lastHeartbeat = now();
    _add(continuation
        ? 'heartbeat'
        : (_foreground ? 'foreground' : 'background'));
    if (_foreground && !continuation) _add('page_view');
  }

  void invalidate() {
    _generation++;
    _owner = null;
    _sessionID = null;
    _queue.clear();
    _sending = false;
    _retryAt = null;
    _failures = 0;
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _add(value ? 'foreground' : 'background');
    if (value) _lastHeartbeat = now();
    unawaited(flush());
  }

  void visit(String page) {
    if (!activityPages.contains(page)) page = 'other';
    if (_page == page) return;
    if (_foreground) _add('page_leave');
    _page = page;
    if (_foreground) _add('page_view');
  }

  void interact() {
    if (!_foreground ||
        (_lastInput != null &&
            now().difference(_lastInput!) < const Duration(seconds: 30))) {
      return;
    }
    _lastInput = now();
    _add('interaction');
  }

  void connection(String event) {
    if (connectionActivities.contains(event)) _add('connection', action: event);
  }

  void action(String action,
      {String? operationID,
      String? clientOrderID,
      String result = 'submitted'}) {
    if (!activityActions.contains(action) ||
        !{'submitted', 'success', 'unconfirmed'}.contains(result)) {
      return;
    }
    _add('action',
        action: action,
        result: result,
        operationID: operationID,
        clientOrderID: clientOrderID);
  }

  void _add(String kind,
      {String? action,
      String? result,
      String? operationID,
      String? clientOrderID}) {
    if (_owner == null || _sessionID == null) return;
    final row = <String, Object>{
      'eventID': newID(),
      'seq': ++_seq,
      'at': now().millisecondsSinceEpoch,
      'kind': kind,
      'page': _page
    };
    if (action != null) row['action'] = action;
    if (result != null) row['result'] = result;
    if (validActivityID(operationID)) row['operationID'] = operationID!;
    if (validActivityID(clientOrderID)) row['clientOrderID'] = clientOrderID!;
    if (_queue.length >= 200) _queue.removeAt(0);
    _queue.add(row);
  }

  void tick() {
    if (_owner == null) return;
    // Bound session duration so daily session aggregates remain useful.
    if (_foreground &&
        _started != null &&
        now().difference(_started!) >= const Duration(minutes: 30) &&
        _queue.isEmpty &&
        !_sending) {
      _start(continuation: true);
    }
    if (_foreground &&
        (_lastHeartbeat == null ||
            now().difference(_lastHeartbeat!) >= const Duration(seconds: 30))) {
      _lastHeartbeat = now();
      _add('heartbeat');
    }
    unawaited(flush());
  }

  Future<void> flush() async {
    final owner = _owner;
    final id = _sessionID;
    if (owner == null ||
        id == null ||
        _sending ||
        _queue.isEmpty ||
        (_retryAt != null && now().isBefore(_retryAt!))) {
      return;
    }
    final generation = _generation;
    final rows = _queue.take(40).toList();
    final ids = rows.map((e) => e['eventID']).toSet();
    _sending = true;
    try {
      final consumed = await upload(owner, {'sessionID': id, 'events': rows});
      if (_generation != generation) return;
      if (consumed) {
        _queue.removeWhere((e) => ids.contains(e['eventID']));
        _retryAt = null;
        _failures = 0;
      } else {
        _backoff();
      }
    } catch (_) {
      if (_generation == generation) _backoff();
    } finally {
      if (_generation == generation) _sending = false;
    }
  }

  void _backoff() {
    _failures++;
    _retryAt = now().add(Duration(seconds: _failures == 1 ? 30 : 60));
  }
}
