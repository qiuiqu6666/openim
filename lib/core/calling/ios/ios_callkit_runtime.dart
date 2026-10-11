import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:openim_common/openim_common.dart' show Config, DataSp, Logger;
import 'package:openim_live/openim_live.dart';

import '../../push/apns/apns_platform.dart';
import 'ios_callkit_platform.dart';
import 'ios_call_invitation.dart';
import 'ios_voip_backend.dart';
import '../data/call_backend_api.dart';

typedef IOSCallKitSession = ({String accountID, String sessionKey});

/// One native provider and one SDK/RTC owner share the same room identity.
/// A PushKit payload alone is not proof that an OpenIM invitation is live.
class IOSCallKitRuntime implements SystemCallAdapter {
  IOSCallKitRuntime({
    required this.sessionReady,
    required this.acceptCall,
    required this.endCall,
    required this.setMicrophone,
    required this.endLiveSession,
    IOSCallKitPlatform? platform,
    IOSCallKitSession? Function()? currentSession,
    void Function(String)? reportStatus,
    bool? supported,
    this.audioTimeout = const Duration(seconds: 15),
    this.invitationWait = const Duration(seconds: 8),
    bool Function(IOSCallInvitation)? restoreInvitation,
    this.resolvePeerName,
    Future<CallBackendApi> Function()? backendApiFactory,
  })  : _platform = platform ?? MethodChannelIOSCallKitPlatform(),
        _credentials = currentSession ?? credentials,
        _report = reportStatus ?? _log,
        _supported = supported ?? Platform.isIOS {
    if (restoreInvitation != null) {
      _backend = IOSVoIPBackend(
        restore: restoreInvitation,
        createApi: backendApiFactory,
        isSessionCurrent: () => _owner != null && _owns(_owner!, _generation),
        endRemote: _endRemote,
        updateName: _updateName,
      );
    }
  }

  IOSVoIPBackend? _backend;
  final Future<String?> Function(String userID)? resolvePeerName;
  final bool Function() sessionReady;
  final Future<bool> Function(String roomID) acceptCall;
  final Future<void> Function(String roomID) endCall;
  final Future<bool> Function(String roomID, bool enabled) setMicrophone;
  final Future<void> Function() endLiveSession;
  final IOSCallKitPlatform _platform;
  final IOSCallKitSession? Function() _credentials;
  final void Function(String) _report;
  final bool _supported;
  final Duration audioTimeout, invitationWait;
  final _calls = <String, SystemCallDescriptor>{};
  final _audio = <String, Completer<bool>>{};
  final _verified = <String, Completer<bool>>{};
  final _answerActions = <String, String>{};
  final _handledActions = <String>{};
  final _audioEnabled = <String>{};
  final _systemMute = <String>{};
  final _pendingEvents = <Map<String, dynamic>>[];
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<APNsDeviceToken>? _tokens;
  IOSCallKitSession? _owner, _blocked;
  Future<void>? _initializing, _preparing, _ending;
  APNsDeviceToken? _voipToken;
  int _generation = 0;
  bool _closed = false, _audioActive = false;
  bool _logoutRequested = false;

  /// PushKit tokens are bound separately from ordinary APNs notification tokens.
  APNsDeviceToken? get voipToken => _voipToken;

  static IOSCallKitSession? credentials() {
    final user = DataSp.userID, token = DataSp.chatToken;
    if (user == null || user.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return (
      accountID: user,
      sessionKey: sha256
          .convert(utf8.encode('$user|$token|${Config.appAuthUrl}'))
          .toString(),
    );
  }

  static void _log(String value) =>
      Logger.print('[iOSCallKit] $value', onlyConsole: true);

  bool _owns(IOSCallKitSession owner, int generation) =>
      !_closed &&
      _owner == owner &&
      _credentials() == owner &&
      _blocked != owner &&
      _generation == generation;

  Future<void> initialize() {
    if (!_supported || _closed) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    _events ??= _platform.events.listen(_receiveEvent);
    _tokens ??= _platform.tokens.listen((value) {
      _voipToken = value;
      _backend?.bind(value);
    });
    try {
      await _platform.initialize();
      final raw = await _platform.invoke<Map>('getCachedTokens');
      if (!_closed) {
        _voipToken = MethodChannelIOSCallKitPlatform.decodeToken(raw);
      }
    } catch (error) {
      _initializing = null;
      _report('native_unavailable:${error.runtimeType}');
      rethrow;
    }
  }

  Future<void> onSessionReady({bool authenticated = false}) async {
    if (!_supported || _closed) return;
    if (authenticated) _blocked = null;
    await _ending;
    if (_closed) return;
    if (!sessionReady()) return;
    final owner = _credentials();
    if (owner == null || _blocked == owner) return;
    if (_owner == owner && _preparing == null) return;
    final pending = _preparing;
    if (pending != null) {
      await pending;
      if (_owner != owner) await onSessionReady();
      return;
    }
    late final Future<void> preparation;
    preparation = _prepare(owner).whenComplete(() {
      if (identical(_preparing, preparation)) _preparing = null;
    });
    _preparing = preparation;
    await preparation;
  }

  Future<void> _prepare(IOSCallKitSession owner) async {
    if (_owner != null && _owner != owner) await endSession(logout: false);
    _owner = owner;
    final generation = ++_generation;
    try {
      await initialize();
      if (!_owns(owner, generation)) return;
      await _platform.invoke<void>('setSession', _identity(owner));
      if (!_owns(owner, generation)) return;
      await _backend?.start(owner.accountID);
      if (!_owns(owner, generation)) return;
      final token = await _platform.invoke<Map>('getCachedTokens');
      if (!_owns(owner, generation)) return;
      _voipToken =
          MethodChannelIOSCallKitPlatform.decodeToken(token) ?? _voipToken;
      _backend?.bind(_voipToken);
      await _platform.invoke<void>('setEventHandlerReady', {'ready': true});
      final nativeEvents = await _platform.invoke<List>('drainPendingEvents');
      if (!_owns(owner, generation)) return;
      final state = await _platform.invoke<Map>('getState');
      if (!_owns(owner, generation)) return;
      _audioActive = state?['audioActive'] == true;
      final pending = List<Map<String, dynamic>>.of(_pendingEvents);
      for (final event in nativeEvents ?? const []) {
        if (event is Map && event.keys.every((key) => key is String)) {
          pending.add(Map<String, dynamic>.from(event));
        }
      }
      _pendingEvents.clear();
      for (final event in pending) {
        // Native setSession adopts only its own persisted, matching account.
        if (event['accountID'] == owner.accountID &&
            event['sessionKey'] == '') {
          event['sessionKey'] = owner.sessionKey;
        }
        _receiveEvent(event);
      }
    } catch (error) {
      if (_owns(owner, generation)) {
        _owner = null;
        _report('session_unavailable:${error.runtimeType}');
      }
    }
  }

  Map<String, dynamic> _identity(IOSCallKitSession owner, [String? room]) => {
        'accountID': owner.accountID,
        'sessionKey': owner.sessionKey,
        if (room != null) 'roomID': room,
      };

  Future<IOSCallKitSession> _admit(SystemCallDescriptor call) async {
    await onSessionReady();
    final owner = _owner;
    if (owner == null ||
        !_owns(owner, _generation) ||
        owner.accountID != call.accountID ||
        !sessionReady()) {
      throw StateError('CallKit session unavailable');
    }
    _calls[call.roomID] = call;
    final waiting = _verified.remove(call.roomID);
    if (waiting != null && !waiting.isCompleted) waiting.complete(true);
    _backend?.monitor(call.roomID, incoming: call.incoming);
    return owner;
  }

  static String _displayName(String? name) =>
      name?.trim().isNotEmpty == true ? name!.trim() : '99chat';

  Future<void> _updateName(String room, String name) async {
    final owner = _owner;
    if (owner == null || !_owns(owner, _generation)) return;
    await _platform.invoke<void>('updateDisplayName', {
      ..._identity(owner, room),
      'displayName': _displayName(name),
    });
  }

  Future<void> _resolveName(SystemCallDescriptor call) async {
    final owner = _owner, generation = _generation;
    if (resolvePeerName == null || owner == null) return;
    try {
      final name = await resolvePeerName!(call.peerUserID);
      if (_owns(owner, generation) &&
          identical(_calls[call.roomID], call) &&
          name?.trim().isNotEmpty == true) {
        await _updateName(call.roomID, name!);
      }
    } catch (_) {/* The system call must not wait on a profile request. */}
  }

  Future<void> _endRemote(String room) async {
    final owner = _owner;
    if (owner == null || !_owns(owner, _generation)) return;
    if (_calls.containsKey(room)) await endCall(room);
    if (_owner == owner) {
      await _platform.invoke<void>('endCall', {
        ..._identity(owner, room),
        'reason': 'remoteEnded',
      });
    }
  }

  @override
  Future<void> reportIncoming(SystemCallDescriptor call) async {
    final payload = {
      'recipientUserID': call.accountID,
      'callerName': _displayName(call.peerName),
      'invitation': call.invitation.toJson(),
    };
    if (IOSCallInvitation.decode(payload, accountID: call.accountID) == null) {
      throw StateError('System invitation invalid or expired');
    }
    final owner = await _admit(call);
    await _platform.invoke<void>('reportIncomingCall', {
      ..._identity(owner, call.roomID),
      ...payload,
    });
    unawaited(_resolveName(call));
  }

  @override
  Future<void> startOutgoing(SystemCallDescriptor call) async {
    final owner = await _admit(call);
    await _platform.invoke<void>('startOutgoingCall', {
      ..._identity(owner, call.roomID),
      'displayName': _displayName(call.peerName),
      'handle': call.peerUserID,
      'hasVideo': call.callType == CallType.video,
    });
    unawaited(_resolveName(call));
  }

  @override
  Future<bool> requestAnswer(SystemCallDescriptor call) async {
    final owner = _owner;
    if (owner == null ||
        !_owns(owner, _generation) ||
        !identical(_calls[call.roomID], call)) {
      return false;
    }
    return await _platform.invoke<bool>(
            'requestAnswer', _identity(owner, call.roomID)) ==
        true;
  }

  @override
  Future<void> transportConnected(SystemCallDescriptor call) async {
    final owner = _owner;
    if (owner == null ||
        !_owns(owner, _generation) ||
        !identical(_calls[call.roomID], call)) {
      throw StateError('CallKit transport belongs to an ended call');
    }
    final action = _answerActions.remove(call.roomID);
    if (call.incoming && action == null) {
      throw StateError('System answer action unavailable');
    }
    if (action != null) {
      await _complete(owner, action, true);
    }
    // CXAnswer must be fulfilled before didActivate can unblock RTC audio.
  }

  @override
  Future<void> peerConnected(SystemCallDescriptor call) async {
    final owner = _owner;
    if (owner == null ||
        !_owns(owner, _generation) ||
        !identical(_calls[call.roomID], call)) {
      return;
    }
    await _platform.invoke<void>(
        'markConnected', _identity(owner, call.roomID));
  }

  @override
  Future<void> microphoneChanged(
      SystemCallDescriptor call, bool enabled) async {
    final owner = _owner;
    if (owner == null ||
        !_owns(owner, _generation) ||
        !identical(_calls[call.roomID], call) ||
        _systemMute.contains(call.roomID)) {
      return;
    }
    final requested = await _platform.invoke<bool>('requestMute', {
      ..._identity(owner, call.roomID),
      'muted': !enabled,
    });
    if (requested != true) {
      _report('system_mute_unavailable');
    }
  }

  @override
  Future<void> speakerChanged(SystemCallDescriptor call, bool enabled) async {
    final owner = _owner;
    if (owner == null ||
        !_owns(owner, _generation) ||
        !identical(_calls[call.roomID], call)) {
      return;
    }
    final routed = await _platform.invoke<bool>('setSpeakerphone', {
      ..._identity(owner, call.roomID),
      'enabled': enabled,
    });
    if (routed != true) {
      throw StateError('System audio route unavailable');
    }
  }

  @override
  Future<void> waitForAudio(SystemCallDescriptor call) async {
    final owner = _owner, generation = _generation;
    if (owner == null || !_owns(owner, generation)) {
      throw StateError('CallKit audio session unavailable');
    }
    final gate = _audio.putIfAbsent(call.roomID, Completer<bool>.new);
    if (_audioActive && !gate.isCompleted) gate.complete(true);
    if (!await gate.future.timeout(audioTimeout) ||
        !_owns(owner, generation) ||
        !identical(_calls[call.roomID], call)) {
      throw StateError('CallKit audio activation cancelled');
    }
    final enabled = await _platform.invoke<bool>('setAudioEnabled', {
      ..._identity(owner, call.roomID),
      'enabled': true,
    });
    if (enabled != true || !_owns(owner, generation)) {
      throw StateError('CallKit audio activation rejected');
    }
    _audioEnabled.add(call.roomID);
  }

  @override
  Future<void> callEnded(
      SystemCallDescriptor call, CallTermination result) async {
    final owner = _owner;
    if (owner == null || !identical(_calls[call.roomID], call)) return;
    _backend?.forget(call.roomID);
    _calls.remove(call.roomID);
    _audioEnabled.remove(call.roomID);
    final gate = _audio.remove(call.roomID);
    if (gate != null && !gate.isCompleted) gate.complete(false);
    final action = _answerActions.remove(call.roomID);
    if (action != null) await _complete(owner, action, false);
    await _platform.invoke<void>('endCall', {
      ..._identity(owner, call.roomID),
      'reason': result.state == CallState.networkError
          ? 'failed'
          : result.state == CallState.timeout
              ? 'unanswered'
              : 'remoteEnded',
    });
    if (_calls.isEmpty) {
      _audioActive = false;
      await _platform.invoke<bool>('releaseAudioSession', _identity(owner));
    }
  }

  void _receiveEvent(Map<String, dynamic> event) {
    if (_closed) return;
    final owner = _owner;
    if (owner == null) {
      if (_blocked == null && _pendingEvents.length < 16) {
        _pendingEvents.add(event);
      }
      return;
    }
    if (!_owns(owner, _generation) ||
        event['accountID'] != owner.accountID ||
        event['sessionKey'] != owner.sessionKey) {
      return;
    }
    final type = event['type'];
    if (type == 'tokenInvalidated') {
      _voipToken = null;
      unawaited(_backend?.invalidateToken());
    } else if (type == 'audioActivated') {
      _audioActive = true;
      for (final gate in _audio.values) {
        if (!gate.isCompleted) gate.complete(true);
      }
      for (final room in _audioEnabled.toList()) {
        unawaited(_resumeAudio(owner, room, _generation));
      }
    } else if (type == 'audioDeactivated') {
      _audioActive = false;
    } else if (type == 'providerReset') {
      unawaited(endSession(logout: false));
    } else if (type == 'incoming') {
      final room = event['roomID'];
      if (room is String && !_calls.containsKey(room)) {
        if (_backend != null) {
          unawaited(_backend!.recover(room));
        } else {
          _report('incoming_requires_live_sdk_invitation');
        }
      }
    } else {
      unawaited(
          _handleAction(event, owner, _generation).catchError((Object error) {
        _report('system_action_unavailable:${error.runtimeType}');
      }));
    }
  }

  Future<void> _handleAction(Map<String, dynamic> event,
      IOSCallKitSession owner, int generation) async {
    final room = event['roomID'],
        type = event['type'],
        action = event['actionID'];
    if (room is! String || room.isEmpty) return;
    if (action is String && !_handledActions.add(action)) return;
    if (_handledActions.length > 256) {
      _handledActions.remove(_handledActions.first);
    }
    if (type == 'answer') {
      if (action is! String || action.isEmpty) return;
      if (!_calls.containsKey(room) && _backend != null) {
        await _backend!.recover(room);
        if (!_owns(owner, generation)) return;
      }
      if (!_calls.containsKey(room)) {
        final gate = _verified.putIfAbsent(room, Completer<bool>.new);
        final verified =
            await gate.future.timeout(invitationWait, onTimeout: () => false);
        if (!verified || !_owns(owner, generation)) {
          if (_owns(owner, generation)) {
            await _complete(owner, action, false);
            await _platform.invoke<void>('endCall', {
              ..._identity(owner, room),
              'reason': 'failed',
            });
          }
          return;
        }
      }
      if (!_owns(owner, generation)) return;
      _answerActions[room] = action;
      if (!await acceptCall(room) && _owns(owner, generation)) {
        if (_answerActions.remove(room) == action) {
          await _complete(owner, action, false);
        }
      }
    } else if (type == 'end' ||
        type == 'actionTimedOut' ||
        type == 'expired' ||
        type == 'ended') {
      if (_calls.containsKey(room)) {
        await endCall(room);
      } else if (type == 'end') {
        await _backend?.rejectCold(room);
      }
      if (type == 'end' && action is String && _owns(owner, generation)) {
        await _complete(owner, action, true);
      }
    } else if (type == 'mute' && action is String) {
      var succeeded = false;
      _systemMute.add(room);
      try {
        succeeded = _calls.containsKey(room) &&
            await setMicrophone(room, event['muted'] != true);
      } finally {
        _systemMute.remove(room);
      }
      if (_owns(owner, generation)) await _complete(owner, action, succeeded);
    }
  }

  Future<void> _resumeAudio(
      IOSCallKitSession owner, String room, int generation) async {
    if (!_owns(owner, generation) || !_calls.containsKey(room)) return;
    try {
      final enabled = await _platform.invoke<bool>('setAudioEnabled', {
        ..._identity(owner, room),
        'enabled': true,
      });
      if (enabled != true && _owns(owner, generation)) await endCall(room);
    } catch (error) {
      if (_owns(owner, generation)) {
        _report('audio_resume_unavailable:${error.runtimeType}');
        await endCall(room);
      }
    }
  }

  Future<void> _complete(
      IOSCallKitSession owner, String action, bool succeeded) async {
    final completed = await _platform.invoke<bool>('completeAction', {
      ..._identity(owner),
      'actionID': action,
      'succeeded': succeeded,
    });
    if (succeeded && completed != true) {
      throw StateError('System call action no longer valid');
    }
  }

  Future<void> endSession({bool logout = true}) {
    if (!_supported || _closed) return Future.value();
    if (_ending != null) {
      if (logout) {
        _blocked = _credentials();
        _logoutRequested = true;
        unawaited(_backend?.stop(logout: true));
      }
      return _ending!;
    }
    final owner = _owner ?? _credentials();
    if (logout) _blocked = owner;
    _logoutRequested = logout;
    final backendStopping = _backend?.stop(logout: logout);
    _generation++;
    _owner = null;
    _pendingEvents.clear();
    _audioActive = false;
    _calls.clear();
    _audioEnabled.clear();
    _systemMute.clear();
    _answerActions.clear();
    _handledActions.clear();
    for (final gate in [..._audio.values, ..._verified.values]) {
      if (!gate.isCompleted) gate.complete(false);
    }
    _audio.clear();
    _verified.clear();
    if (logout) _voipToken = null;
    late final Future<void> ending;
    ending = Future.wait([
      if (backendStopping != null) backendStopping,
      _endSession(owner, logout),
    ]).then((_) {}).whenComplete(() {
      if (identical(_ending, ending)) _ending = null;
    });
    return _ending = ending;
  }

  Future<void> _endSession(IOSCallKitSession? owner, bool logout) async {
    try {
      await initialize();
      final state = await _platform.invoke<Map>('getState');
      await _platform.invoke<void>('pauseSession', {
        'sessionKey': state?['sessionKey'] ?? '',
        'logout': _logoutRequested,
      });
    } catch (error) {
      _report('session_cleanup_unavailable:${error.runtimeType}');
    } finally {
      try {
        await endLiveSession();
        if (!logout && _logoutRequested) {
          final state = await _platform.invoke<Map>('getState');
          await _platform.invoke<void>('pauseSession', {
            'sessionKey': state?['sessionKey'] ?? '',
            'logout': true,
          });
        }
        if (owner != null) {
          await _platform.invoke<bool>('releaseAudioSession', _identity(owner));
        }
      } catch (error) {
        _report('media_cleanup_unavailable:${error.runtimeType}');
      }
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    await endSession();
    _closed = true;
    await _events?.cancel();
    await _tokens?.cancel();
    await _platform.dispose();
  }
}
