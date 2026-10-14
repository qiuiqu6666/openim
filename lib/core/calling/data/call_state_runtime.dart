import 'dart:async';
import 'dart:convert';

import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

import 'call_backend_api.dart';
import 'call_state_heartbeat.dart';
import 'call_state_snapshot.dart';

/// Shared by Android, in-app iOS calls and PushKit recovery. Status reads never
/// renew leases. A server update can only close the matching local room.
class CallStateRuntime {
  CallStateRuntime({Future<CallBackendApi> Function()? createApi})
      : _createApi = createApi ?? CallBackendApi.current;
  static final instance = CallStateRuntime();
  final Future<CallBackendApi> Function() _createApi;
  Future<void> Function(CallStateSnapshot, String)? onState;
  bool Function(CallStateSnapshot)? restoreIncoming;
  String? Function()? activeRoom;
  bool Function()? ready;
  CallBackendApi? _api;
  Future<CallBackendApi>? _opening;
  Future<void>? _reconciling;
  final _snapshots = <String, CallStateSnapshot>{};
  final _reads = <String, Future<CallStateSnapshot>>{};
  final _hints = <String, int>{};
  final _localRooms = <String>{};
  final _subscriptions = <StreamSubscription>[];
  Timer? _poll;
  int _generation = 0;
  bool _enabled = false;
  bool _polling = false;
  (String?, String?)? _credentials;

  void bind({required Stream<String> business, required Stream<void> recovery}) {
    for (final subscription in _subscriptions) { unawaited(subscription.cancel()); }
    _subscriptions.clear();
    _subscriptions.add(business.listen(_notification));
    _subscriptions.add(recovery.listen((_) => recover()));
  }

  void activate() {
    final credentials = (DataSp.userID, DataSp.chatToken);
    if (_credentials != credentials) reset();
    _credentials = credentials;
    _enabled = true;
  }

  bool _owns(CallBackendApi api, int generation) => _enabled &&
      generation == _generation && identical(_api, api) && api.isCurrent;

  Future<CallBackendApi> _transport() async {
    if (!_enabled) throw const CallRequestCancelled();
    if (_credentials != (DataSp.userID, DataSp.chatToken)) {
      reset();
      throw const CallRequestCancelled();
    }
    final existing = _api;
    if (existing != null && existing.isCurrent) return existing;
    if (existing != null) {
      reset();
      throw const CallRequestCancelled();
    }
    final pending = _opening;
    if (pending != null) return pending;
    final generation = _generation;
    late Future<CallBackendApi> opening;
    opening = _createApi().then((api) {
      if (!_enabled || generation != _generation || !api.isCurrent) {
        api.close();
        throw const CallRequestCancelled();
      }
      return _api = api;
    }).whenComplete(() { if (identical(_opening, opening)) _opening = null; });
    return _opening = opening;
  }

  CallStateSnapshot _apply(CallBackendApi api, int generation,
      Map<String, dynamic> raw, {String? room, bool notify = true}) {
    if (!_owns(api, generation)) throw const CallRequestCancelled();
    final next = CallStateSnapshot.decode(raw, api.accountID, room: room);
    final old = _snapshots[next.room];
    // Legacy revision 0 may advance from ringing to accepted/terminal, but can
    // never regress. Modern revisions are strictly increasing per room.
    if (old != null && (old.terminal ||
        (old.state == 'accepted' && next.ringing) || next.revision < old.revision ||
        (next.revision == old.revision && !(next.revision == 0 &&
            (next.terminal || (old.ringing && next.state == 'accepted')))))) {
      _lease(api, generation, old);
      return old;
    }
    _snapshots[next.room] = next;
    while (_snapshots.length > 256) {
      final victims = _snapshots.keys.where((key) => !_localRooms.contains(key));
      if (victims.isEmpty) break;
      _snapshots.remove(victims.first);
    }
    _lease(api, generation, next);
    // Do not await local RTC teardown from inside its own accept/hangup await.
    final callback = onState;
    if (notify && callback != null) {
      unawaited(Future<void>.sync(() {
        if (_owns(api, generation)) return callback(next, api.deviceID);
      }).catchError((Object error) => _log(error)));
    }
    return next;
  }

  void _lease(CallBackendApi api, int generation, CallStateSnapshot value) {
    if (value.state == 'accepted' && _localRooms.contains(value.room) &&
        value.participant(api.accountID, api.deviceID)) {
      CallStateHeartbeat.start(value.room, api, onSnapshot: (raw) {
        if (_owns(api, generation)) _apply(api, generation, raw, room: value.room);
      });
    } else {
      CallStateHeartbeat.stop(value.room);
      if (value.terminal || value.answeredElsewhere(api.accountID, api.deviceID)) {
        _localRooms.remove(value.room);
      }
    }
    _schedulePoll();
  }

  Future<CallStateSnapshot> status(String room) async {
    final generation = _generation;
    final api = await _transport();
    if (!_owns(api, generation)) throw const CallRequestCancelled();
    final existing = _reads[room];
    if (existing != null) return existing;
    late Future<CallStateSnapshot> request;
    request = api.status(room).then((raw) =>
        _apply(api, generation, raw, room: room)).whenComplete(() {
      if (identical(_reads[room], request)) _reads.remove(room);
    });
    return _reads[room] = request;
  }

  Future<bool> admitIncoming(InvitationInfo invitation) async {
    if (!validCallInvitation(invitation) || invitation.sessionType != 1) return false;
    final generation = _generation;
    final api = await _transport();
    if (!_owns(api, generation)) return false;
    final value = await status(invitation.roomID!);
    if (!_owns(api, generation) || !value.ringing || value.expiredInvitation ||
        !value.incoming(api.accountID) ||
        value.invitation.inviterUserID != invitation.inviterUserID ||
        value.invitation.mediaType != invitation.mediaType) return false;
    _localRooms.add(value.room);
    _schedulePoll();
    return true;
  }

  Future<void> persist(int type, InvitationInfo invitation) async {
    final generation = _generation;
    final api = await _transport();
    if (!_owns(api, generation)) throw const CallRequestCancelled();
    final room = invitation.roomID!;
    _localRooms.add(room);
    final action = switch (type) {
      CustomMessageType.callingInvite => 'invite',
      CustomMessageType.callingAccept => 'accept',
      CustomMessageType.callingReject => 'reject',
      CustomMessageType.callingCancel => 'cancel',
      CustomMessageType.callingHungup => 'hangup',
      _ => throw const CallBackendException(400),
    };
    var operation = action;
    if (action != 'invite' && action != 'accept') {
      // Never send a loser-device reject/hangup. The server is still the final
      // authority if another device accepts after this read.
      try {
        final before = await status(room);
        if (!_owns(api, generation)) throw const CallRequestCancelled();
        if (before.terminal || before.answeredElsewhere(api.accountID, api.deviceID)) {
          throw const CallRequestCancelled();
        }
        if (before.state == 'accepted') {
          if (!before.participant(api.accountID, api.deviceID)) {
            throw const CallRequestCancelled();
          }
          operation = 'hangup';
        }
      } on CallBackendException catch (error) {
        // A cancellation can overtake its invite; preserve the original
        // invitation so the server can atomically create a terminal record.
        if (error.code != 404 || action != 'cancel') rethrow;
      }
    }
    CallStateSnapshot value;
    try {
      final raw = action == 'invite' ? await api.invite(invitation) :
          await api.request('action', {'callID': room, 'deviceID': api.deviceID,
            'action': operation, 'invitation': invitation.toJson()});
      value = _apply(api, generation, raw, room: room,
          notify: action == 'invite' || action == 'accept' ||
              !const ['rejected', 'cancelled', 'ended', 'expired'].contains(raw['state']));
    } catch (error) {
      if (!_owns(api, generation)) throw const CallRequestCancelled();
      try {
        value = await status(room);
      } catch (_) {
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      if (!_owns(api, generation)) throw const CallRequestCancelled();
      // Even an observed accepted snapshot cannot turn an authorization error
      // into permission to enter RTC or send an accept signal.
      if (error is CallBackendException &&
          (error.authorizationFailed || error.code != 409)) {
        rethrow;
      }
      if (value.answeredElsewhere(api.accountID, api.deviceID) || value.terminal) {
        throw const CallRequestCancelled();
      }
      final committed = action == 'accept'
          ? value.state == 'accepted' && value.answeredDevice == api.deviceID
          : action == 'invite' && value.ringing && value.callerDevice == api.deviceID;
      if (!committed) rethrow;
    }
    if (!_owns(api, generation)) throw const CallRequestCancelled();
    if (action == 'accept' &&
        (value.state != 'accepted' || value.answeredDevice != api.deviceID)) {
      throw const CallRequestCancelled();
    }
    if (action == 'invite' &&
        (!value.ringing || value.callerDevice != api.deviceID)) {
      throw const CallRequestCancelled();
    }
    if (action != 'accept' && action != 'invite' && !value.terminal) {
      throw const CallBackendException(409);
    }
  }

  void release(String room) {
    _localRooms.remove(room);
    CallStateHeartbeat.stop(room);
    _schedulePoll();
    // Local teardown never emits an implicit server hangup.
  }

  void watchRoom(String room) {
    if (!_enabled || _snapshots[room]?.ringing != true) return;
    _localRooms.add(room);
    _schedulePoll();
  }

  void _schedulePoll() {
    if (!_enabled || _polling) return;
    final rooms = _localRooms.where((room) => _snapshots[room]?.ringing == true);
    if (rooms.isEmpty) { _poll?.cancel(); _poll = null; return; }
    _poll ??= Timer(const Duration(seconds: 2), () async {
      _poll = null;
      _polling = true;
      final generation = _generation;
      try {
        for (final room in rooms.toList()) {
          try { await status(room); } catch (error) { _log(error); }
          if (generation != _generation || !_enabled) return;
        }
      } finally {
        if (generation == _generation) {
          _polling = false;
          _schedulePoll();
        }
      }
    });
  }

  void _notification(String raw) {
    if (!_enabled) return;
    try {
      dynamic envelope = jsonDecode(raw);
      if (envelope is Map && envelope['notificationElem'] is Map) {
        envelope = envelope['notificationElem']['detail'];
      } else if (envelope is Map && envelope['detail'] != null) {
        envelope = envelope['detail'];
      }
      if (envelope is String) envelope = jsonDecode(envelope);
      if (envelope is! Map || envelope['key'] != 'callStateChanged') return;
      dynamic event = envelope['data'];
      if (event is String) event = jsonDecode(event);
      if (event is! Map || event['callID'] is! String) return;
      final room = event['callID'] as String;
      final revision = event['revision'] ?? 0;
      if (!validCallID(room) || revision is! int || revision < 0) return;
      final known = _snapshots[room];
      if (known != null && (known.terminal ||
          (revision > 0 && revision <= known.revision))) return;
      if (_hints.containsKey(room)) {
        if (revision > _hints[room]!) _hints[room] = revision;
        return;
      }
      if (_hints.length >= 16) return;
      _hints[room] = revision;
      unawaited(_resolveHint(room, _generation));
    } catch (_) { /* A malformed business notice cannot start a call. */ }
  }

  Future<void> _resolveHint(String room, int generation) async {
    try {
      for (var pass = 0; pass < 2; pass++) {
        if (generation != _generation || !_enabled) return;
        final revision = _hints[room];
        final value = await status(room);
        if (generation != _generation || !_enabled) return;
        _restore(value);
        if (_hints[room] == revision || value.revision >= (_hints[room] ?? 0)) break;
      }
    } catch (error) { _log(error); }
    finally { if (generation == _generation) _hints.remove(room); }
  }

  void recover() {
    if (!_enabled || ready?.call() != true || _reconciling != null) return;
    late Future<void> pending;
    pending = _recover().catchError((Object error) => _log(error)).whenComplete(() {
      if (identical(_reconciling, pending)) _reconciling = null;
    });
    _reconciling = pending;
  }

  Future<void> _recover() async {
    final generation = _generation;
    final api = await _transport();
    if (!_owns(api, generation)) return;
    final room = activeRoom?.call();
    if (room != null) {
      try { await status(room); } catch (error) { _log(error); }
      if (!_owns(api, generation)) return;
    }
    final response = await api.currentCall();
    if (!_owns(api, generation)) return;
    final current = response['call'];
    if (current is Map) {
      _restore(_apply(api, generation, Map<String, dynamic>.from(current)));
    }
    // null is not an invitation and never resurrects an old local room.
  }

  void _restore(CallStateSnapshot value) {
    final api = _api;
    if (api == null || !api.isCurrent || !value.ringing || value.expiredInvitation ||
        !value.incoming(api.accountID) || ready?.call() != true) return;
    if (restoreIncoming?.call(value) == true) {
      _localRooms.add(value.room);
      _schedulePoll();
    }
  }

  void reset() {
    _enabled = false;
    _credentials = null;
    ++_generation;
    _poll?.cancel(); _poll = null;
    _polling = false;
    CallStateHeartbeat.stopAll();
    _api?.close(); _api = null;
    _opening = null; _reconciling = null;
    _snapshots.clear(); _reads.clear(); _hints.clear(); _localRooms.clear();
  }

  void close() {
    reset();
    for (final subscription in _subscriptions) { unawaited(subscription.cancel()); }
    _subscriptions.clear();
    onState = null; restoreIncoming = null; activeRoom = null; ready = null;
  }

  static void _log(Object error) => Logger.print(
      'Call state reconciliation unavailable: ${error.runtimeType}', onlyConsole: true);
}
