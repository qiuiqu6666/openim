import 'activity_collector.dart';

/// Tracks SDK connection transitions within one credential pair. Initial
/// connection and repeated success callbacks are not reconnections.
class ConnectionActivity {
  ActivitySession? owner;
  bool _connectedOnce = false, _disconnected = false;
  bool _restoreRequested = false, _restoreRecorded = false;
  final List<String> _pending = [];

  void begin(ActivitySession? session) {
    reset();
    owner = session;
  }

  void lost() {
    if (owner == null || !_connectedOnce || _disconnected) return;
    _disconnected = true;
    _add('connection_lost');
  }

  void connected() {
    if (owner == null) return;
    final reconnect = _connectedOnce && _disconnected;
    _connectedOnce = true;
    _disconnected = false;
    _recordRestore();
    if (reconnect) _add('reconnect');
  }

  void restored() {
    if (owner == null) return;
    _restoreRequested = true;
    _recordRestore();
  }

  void _recordRestore() {
    if (_restoreRequested && _connectedOnce && !_restoreRecorded) {
      _restoreRecorded = true;
      _add('session_restore');
    }
  }

  void _add(String value) {
    if (_pending.length == 20) _pending.removeAt(0);
    _pending.add(value);
  }

  List<String> take(ActivitySession? session) {
    if (owner == null || session != owner) return [];
    final events = List<String>.of(_pending);
    _pending.clear();
    return events;
  }

  void reset() {
    owner = null;
    _connectedOnce = _disconnected = false;
    _restoreRequested = _restoreRecorded = false;
    _pending.clear();
  }
}
