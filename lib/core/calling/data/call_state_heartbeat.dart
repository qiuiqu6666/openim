import 'dart:async';

import 'package:openim_common/openim_common.dart';

import 'call_backend_api.dart';

/// Keeps a live call's server lease on Android as well as iOS. If both apps
/// disappear, the lease expires so a stale call cannot block the next caller.
class CallStateHeartbeat {
  static final _calls = <String, CallStateHeartbeat>{};

  static void start(String room, CallBackendApi api) {
    stop(room);
    _calls[room] = CallStateHeartbeat._(room, api);
  }

  static void stop(String room) {
    final old = _calls.remove(room);
    old?._timer.cancel();
    old?._api.close();
  }

  static void stopAll() {
    for (final room in _calls.keys.toList()) {
      stop(room);
    }
  }

  static Future<void> finish(String room) async {
    final old = _calls.remove(room);
    if (old == null) return;
    old._timer.cancel();
    try {
      final status = await old._api.status(room);
      if (status['state'] == 'accepted') {
        await old._api.action(room, 'hangup');
      } else if (status['state'] == 'ringing') {
        final invitation = status['invitation'];
        if (invitation is Map) {
          await old._api.action(
              room,
              invitation['inviterUserID'] == old._api.accountID
                  ? 'cancel'
                  : 'reject');
        }
      }
    } catch (_) {
      /* The server lease also releases abandoned calls. */
    } finally {
      old._api.close();
    }
  }

  CallStateHeartbeat._(this._room, this._api) {
    _timer =
        Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_tick()));
  }

  final String _room;
  final CallBackendApi _api;
  late final Timer _timer;
  bool _pending = false;

  Future<void> _tick() async {
    if (_pending) return;
    if (DataSp.userID != _api.accountID ||
        DataSp.chatToken != _api.token ||
        Config.appAuthUrl.replaceFirst(RegExp(r'/+$'), '') != _api.baseUrl) {
      stop(_room);
      return;
    }
    _pending = true;
    try {
      final state = await _api.status(_room);
      if (identical(_calls[_room], this) &&
          !const ['ringing', 'accepted'].contains(state['state'])) {
        stop(_room);
      }
    } catch (_) {
      /* The bounded server lease tolerates transient failures. */
    } finally {
      _pending = false;
    }
  }
}
