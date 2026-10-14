import 'dart:async';

import 'package:openim_common/openim_common.dart';

import '../data/call_backend_api.dart';
import '../data/call_state_runtime.dart';
import '../../push/apns/apns_platform.dart';
import 'ios_call_invitation.dart';

/// Session-owned token binding and authoritative cold-call recovery. The native
/// layer reports immediately; network access is only for business admission.
class IOSVoIPBackend {
  IOSVoIPBackend(
      {required this.restore,
      required this.endRemote,
      required this.updateName,
      required this.isSessionCurrent,
      Future<CallBackendApi> Function()? createApi,
      CallStateRuntime? runtime,
      this.pollInterval = const Duration(seconds: 2)})
      : _createApi = createApi ?? CallBackendApi.current,
        _runtime = runtime ?? CallStateRuntime.instance;

  final bool Function(IOSCallInvitation) restore;
  final Future<void> Function(String) endRemote;
  final Future<void> Function(String, String) updateName;
  final bool Function() isSessionCurrent;
  final Future<CallBackendApi> Function() _createApi;
  final CallStateRuntime _runtime;
  final Duration pollInterval;
  CallBackendApi? _api, _pausedApi;
  Future<void>? _stopping;
  bool _logoutRequested = false;
  APNsDeviceToken? _token;
  Timer? _retryBinding;
  Future<void> _binding = Future.value();
  final _recovering = <String, Future<bool>>{};
  final _ended = <String>{};
  int _generation = 0;

  bool _owns(CallBackendApi api, int generation) =>
      identical(_api, api) && _generation == generation &&
      isSessionCurrent() && api.isCurrent;

  Future<void> start(String accountID) async {
    await _stopping;
    final generation = ++_generation;
    final api = await _createApi();
    if (generation != _generation ||
        !isSessionCurrent() ||
        api.accountID != accountID) {
      api.close();
      return;
    }
    _api?.close();
    _pausedApi?.close();
    _pausedApi = null;
    _api = api;
    _ended.clear();
    bind(_token);
  }

  void bind(APNsDeviceToken? token) {
    _token = token;
    _retryBinding?.cancel();
    final api = _api, generation = _generation;
    if (api == null || token == null) return;
    _binding = _binding.then((_) async {
      if (!_owns(api, generation) || _token != token) return;
      try {
        await api.bind(token);
      } catch (error) {
        if (_owns(api, generation)) {
          _retryBinding = Timer(const Duration(seconds: 5), () => bind(_token));
        }
        Logger.print('VoIP registration unavailable: ${error.runtimeType}',
            onlyConsole: true);
      }
    });
  }

  void monitor(String room, {required bool incoming}) {
    if (!_ended.contains(room)) _runtime.watchRoom(room);
  }

  Future<bool> recover(String room) {
    final existing = _recovering[room];
    if (existing != null) return existing;
    late Future<bool> request;
    request = _recover(room).whenComplete(() {
      if (identical(_recovering[room], request)) _recovering.remove(room);
    });
    _recovering[room] = request;
    return request;
  }

  Future<bool> _recover(String room) async {
    final api = _api, generation = _generation;
    if (api == null || !_owns(api, generation) || _ended.contains(room)) return false;
    try {
      final snapshot = await _runtime.status(room);
      final status = snapshot.raw;
      if (!_owns(api, generation) || _ended.contains(room)) return false;
      if (status['state'] != 'ringing') {
        await endRemote(room);
        return false;
      }
      final invitation =
          IOSCallInvitation.decode(status, accountID: api.accountID);
      if (invitation == null || invitation.roomID != room) {
        await endRemote(room);
        return false;
      }
      if (!restore(invitation)) {
        await endRemote(room);
        return false;
      }
      monitor(room, incoming: true);
      await updateName(room, invitation.callerName);
      return _owns(api, generation) && !_ended.contains(room);
    } catch (error) {
      Logger.print('VoIP recovery unavailable: ${error.runtimeType}',
          onlyConsole: true);
      if (_owns(api, generation) && error is CallBackendException &&
          (error.authorizationFailed || error.code == 404)) await endRemote(room);
      return false;
    }
  }


  Future<void> invalidateToken() async {
    _token = null;
    _retryBinding?.cancel();
    final api = _api;
    await _binding;
    if (api != null) {
      try {
        await api.unbind();
      } catch (_) {}
    }
  }

  Future<void> rejectCold(String room) async {
    forget(room);
    final api = _api, generation = _generation;
    if (api == null || !_owns(api, generation)) return;
    try {
      final state = await _runtime.status(room);
      if (!_owns(api, generation) || !state.incoming(api.accountID)) return;
      await _runtime.persist(
          CustomMessageType.callingReject, state.invitation);
    } catch (error) {
      Logger.print('Cold call rejection unavailable: ${error.runtimeType}',
          onlyConsole: true);
    } finally {
      if (_owns(api, generation)) _runtime.release(room);
    }
  }

  void forget(String room) {
    _ended.add(room);
    if (_ended.length > 256) _ended.remove(_ended.first);
  }

  Future<void> stop({required bool logout}) {
    final pending = _stopping;
    if (pending != null) {
      _logoutRequested = _logoutRequested || logout;
      return pending;
    }
    _logoutRequested = logout;
    _generation++;
    final api = _api ?? _pausedApi;
    _api = null;
    _pausedApi = null;
    _retryBinding?.cancel();
    _ended.clear();
    _recovering.clear();
    late Future<void> stopping;
    stopping = _finishStop(api).whenComplete(() {
      if (identical(_stopping, stopping)) _stopping = null;
    });
    return _stopping = stopping;
  }

  Future<void> _finishStop(CallBackendApi? api) async {
    // A logout arriving during SDK re-login upgrades the pending pause. Keep
    // the captured transport across a completed pause for a later logout too.
    await _binding;
    if (_logoutRequested) {
      _token = null;
      if (api != null) {
        try {
          await api.unbind();
        } catch (error) {
          Logger.print('VoIP cleanup unavailable: ${error.runtimeType}',
              onlyConsole: true);
        }
      }
      api?.close();
    } else {
      _pausedApi = api;
    }
  }
}
