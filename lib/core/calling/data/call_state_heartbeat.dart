import 'dart:async';

import 'call_backend_api.dart';

/// A lease belongs to one accepted participant, never to an observing device.
class CallStateHeartbeat {
  static final _calls = <String, CallStateHeartbeat>{};

  static void start(String room, CallBackendApi api,
      {required void Function(Map<String, dynamic>) onSnapshot}) {
    final old = _calls[room];
    if (old != null && identical(old._api, api)) return;
    stop(room);
    final value = _calls[room] = CallStateHeartbeat._(room, api, onSnapshot);
    unawaited(value._tick());
  }

  static void stop(String room) => _calls.remove(room)?._timer?.cancel();

  static void stopAll() {
    for (final room in _calls.keys.toList()) {
      stop(room);
    }
  }

  CallStateHeartbeat._(this._room, this._api, this._onSnapshot);
  final String _room;
  final CallBackendApi _api;
  final void Function(Map<String, dynamic>) _onSnapshot;
  Timer? _timer;
  bool get _current => identical(_calls[_room], this) && _api.isCurrent;

  Future<void> _tick() async {
    if (!_current) {
      if (identical(_calls[_room], this)) stop(_room);
      return;
    }
    var delay = const Duration(seconds: 10);
    try {
      final value = await _api.heartbeat(_room);
      if (_current) _onSnapshot(value);
    } catch (_) {
      // One failed request is not a remote hangup. Retry without overlap.
      delay = const Duration(seconds: 3);
    } finally {
      if (_current) {
        _timer = Timer(delay, () => unawaited(_tick()));
      } else if (identical(_calls[_room], this)) {
        stop(_room);
      }
    }
  }
}
