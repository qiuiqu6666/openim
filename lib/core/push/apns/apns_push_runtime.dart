import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:openim_common/openim_common.dart' show Config, DataSp, Logger;

import 'apns_platform.dart';
import 'apns_token_api.dart';

typedef APNsPushSession = ({
  String accountID,
  String token,
  String endpoint,
  String sessionKey,
});
typedef APNsApiFactory = ApnsTokenApi Function(
    APNsPushSession session, String deviceID);

typedef _APNsDeviceScope = ({
  String endpoint,
  String accountID,
  String deviceID
});

class _PendingAPNsCleanup {
  _PendingAPNsCleanup(this.owner, this.transport, this.bindingRevision);

  final APNsPushSession owner;
  final int bindingRevision;
  ApnsTokenApi? transport;
  DateTime? retryAfter;
  bool queued = false;

  _APNsDeviceScope? get scope => transport == null
      ? null
      : (
          endpoint: transport!.baseUrl,
          accountID: owner.accountID,
          deviceID: transport!.deviceID
        );
}

/// One owner for Apple registration, account binding and logout barriers.
/// Upload and deletion are serialized so an old upload cannot undo logout.
class APNsPushRuntime {
  APNsPushRuntime({
    required this.sessionReady,
    required this.onNotificationTap,
    APNsPlatform? platform,
    APNsPushSession? Function()? currentSession,
    Future<String> Function()? deviceID,
    APNsApiFactory? apiFactory,
    bool Function(String accountID)? notificationsEnabled,
    void Function(String)? reportStatus,
    bool? supported,
    DateTime Function()? now,
    this.retryDelay = const Duration(seconds: 30),
  })  : _platform = platform ?? MethodChannelAPNsPlatform(),
        _credentials = currentSession ?? credentials,
        _deviceID = deviceID ?? DataSp.ensureLoginDeviceID,
        _apiFactory = apiFactory ?? _api,
        _notificationsEnabled = notificationsEnabled ?? ((_) => true),
        _report = reportStatus ?? _log,
        _supported = supported ?? Platform.isIOS,
        _now = now ?? DateTime.now;

  final bool Function() sessionReady;
  final Future<void> Function(Map<String, dynamic>) onNotificationTap;
  final APNsPlatform _platform;
  final APNsPushSession? Function() _credentials;
  final Future<String> Function() _deviceID;
  final APNsApiFactory _apiFactory;
  final bool Function(String accountID) _notificationsEnabled;
  final void Function(String) _report;
  final bool _supported;
  final DateTime Function() _now;
  final Duration retryDelay;

  APNsPushSession? _owner, _blocked;
  final _completedCleanups = <APNsPushSession>{};
  final _pendingCleanups = <_PendingAPNsCleanup>[];
  final _bindingRevisions = <_APNsDeviceScope, int>{};
  ApnsTokenApi? _transport;
  APNsDeviceToken? _wanted, _uploaded, _queued;
  StreamSubscription<APNsDeviceToken>? _tokenSubscription;
  StreamSubscription<Map<String, dynamic>>? _tapSubscription;
  StreamSubscription<int>? _errorSubscription;
  Future<void>? _preparing, _ending;
  Future<void> _serverOperations = Future<void>.value();
  Future<void> _platformOperations = Future<void>.value();
  DateTime? _retryAfter, _uploadedAt;
  int _generation = 0;
  int _bindingRevision = 0;
  int _registrationFailureEpoch = 0;
  bool _initialized = false,
      _nativeRegistered = false,
      _nativeCleared = false,
      _tapsActivated = false,
      _bindingDisabled = false,
      _disabledUnbound = false,
      _rebindRequested = false,
      _disposing = false,
      _closed = false;

  static const bindingRenewalInterval = Duration(hours: 24);

  static APNsPushSession? credentials() {
    final account = DataSp.userID, token = DataSp.imToken;
    if (account == null || account.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return (
      accountID: account,
      token: token,
      endpoint: Config.imApiUrl,
      sessionKey: sha256.convert(utf8.encode('$account|$token')).toString(),
    );
  }

  static ApnsTokenApi _api(APNsPushSession owner, String deviceID) =>
      ApnsTokenApi(
          baseUrl: owner.endpoint,
          imToken: owner.token,
          userID: owner.accountID,
          deviceID: deviceID);
  static void _log(String status) =>
      Logger.print('[APNs] $status', onlyConsole: true);

  bool _owns(APNsPushSession owner, int generation) =>
      !_closed &&
      _owner == owner &&
      _credentials() == owner &&
      _blocked != owner &&
      _generation == generation;

  bool _canBind(APNsPushSession owner, int generation) =>
      _owns(owner, generation) &&
      !_bindingDisabled &&
      _notificationsEnabled(owner.accountID);

  bool get _bindingExpired =>
      _uploadedAt != null &&
      !_now().isBefore(_uploadedAt!.add(bindingRenewalInterval));

  /// Called only for an actual application foreground transition.
  Future<void> onForeground() {
    final owner = _owner;
    if (!_disposing && owner != null && _canBind(owner, _generation)) {
      // A reconnecting SDK may not be ready yet. Keep this renewal request
      // until the same authenticated session becomes ready again.
      _rebindRequested = true;
    }
    return onSessionReady(forceRebind: true);
  }

  /// Preference events are account-scoped and never authorize a signed-out
  /// session. Closing notifications fences pending uploads before deletion.
  Future<void> onPreferencesChanged(String accountID) async {
    if (_closed || _disposing || !_supported) return;
    final owner = _owner;
    if (owner == null ||
        owner.accountID != accountID ||
        _credentials() != owner ||
        _blocked == owner) {
      return;
    }
    _applyBindingPreference(owner);
    if (_bindingDisabled) {
      await _prepareOwner(owner);
    } else {
      await onSessionReady();
    }
  }

  Future<void> onSessionReady(
      {bool authenticated = false, bool forceRebind = false}) async {
    if (_closed || _disposing || !_supported) return;
    _retryPendingCleanups();
    // SDK sync may finish while splash/login still covers the home route.
    // Preserve its authentication grant until navigation becomes ready.
    if (authenticated) _blocked = null;
    if (!sessionReady()) return;
    final owner = _credentials();
    if (owner == null || _blocked == owner) return;
    if (_owner != owner) {
      _retireOwner();
      _owner = owner;
    }
    _applyBindingPreference(owner);
    if (forceRebind && !_bindingDisabled) _rebindRequested = true;
    await _prepareOwner(owner);
  }

  void _applyBindingPreference(APNsPushSession owner) {
    final disabled = !_notificationsEnabled(owner.accountID);
    if (_bindingDisabled == disabled) return;
    _generation++;
    _bindingDisabled = disabled;
    _disabledUnbound = false;
    _wanted = _uploaded = _queued = null;
    _uploadedAt = _retryAfter = null;
    _rebindRequested = false;
    _nativeRegistered = false;
  }

  Future<void> _prepareOwner(APNsPushSession owner) async {
    final pending = _preparing;
    if (pending != null) {
      await pending;
      if (!_closed &&
          !_disposing &&
          _owner == owner &&
          _credentials() == owner &&
          (_transport == null ||
              (_bindingDisabled ? !_disabledUnbound : !_nativeRegistered) ||
              _rebindRequested)) {
        await _prepareOwner(owner);
      }
      return;
    }
    final generation = _generation;
    late final Future<void> preparation;
    preparation = _prepare(owner, generation).whenComplete(() {
      if (identical(_preparing, preparation)) _preparing = null;
    });
    _preparing = preparation;
    await preparation;
  }

  Future<void> _prepare(APNsPushSession owner, int generation) async {
    if (_retryAfter != null && _now().isBefore(_retryAfter!)) return;
    try {
      // Tap handling remains available for notifications already delivered,
      // even when this account has disabled future offline notifications.
      if (!_initialized) {
        _tokenSubscription ??= _platform.tokens.listen(_receiveToken);
        _errorSubscription ??= _platform.registrationErrors.listen((code) {
          final active = _owner;
          if (active == null || !_canBind(active, _generation)) return;
          _registrationFailureEpoch++;
          _nativeRegistered = false;
          _retryAfter = _now().add(retryDelay);
          _report('native_registration_failed:$code');
        });
        _tapSubscription ??= _platform.notificationTaps.listen((payload) {
          final active = _credentials();
          if (active == null || _blocked == active || _closed) return;
          unawaited(_handleTap(payload, active, _generation));
        });
        try {
          await _platform.initialize();
          if (!_owns(owner, generation)) return;
          _initialized = true;
        } catch (error) {
          if (!_owns(owner, generation)) return;
          if (!_bindingDisabled) rethrow;
          _report('notification_tap_bridge_unavailable:${error.runtimeType}');
        }
      }
      if (_initialized && !_tapsActivated) {
        var activated = false;
        await _native(() async {
          if (!_owns(owner, generation)) return;
          _nativeCleared = false;
          await _platform.activateNotificationTaps();
          activated = true;
        });
        if (!_owns(owner, generation)) return;
        _tapsActivated = activated;
        if (!activated && !_bindingDisabled) {
          _retryAfter = _now().add(retryDelay);
          return;
        }
      }
      if (_bindingDisabled) {
        if (_disabledUnbound) return;
        await _ensureTransport(owner, generation);
        final transport = _transport;
        if (!_owns(owner, generation) || transport == null) return;
        await _server(() async {
          if (!_owns(owner, generation) || !_bindingDisabled) return;
          try {
            await transport.delete();
            if (!_owns(owner, generation) || !_bindingDisabled) return;
            _disabledUnbound = true;
            _retryAfter = null;
            _report('device_notifications_disabled');
          } catch (error) {
            if (!_owns(owner, generation)) return;
            _retryAfter = _now().add(retryDelay);
            _report('device_cleanup_unavailable:${error.runtimeType}');
          }
        });
        return;
      }
      await _ensureTransport(owner, generation);
      if (!_canBind(owner, generation)) return;
      final registrationEpoch = _registrationFailureEpoch;
      if (!_nativeRegistered) {
        var allowed = false;
        await _native(() async {
          if (!_canBind(owner, generation)) return;
          allowed = await _platform.register();
        });
        if (!_canBind(owner, generation) ||
            registrationEpoch != _registrationFailureEpoch) {
          return;
        }
        if (!allowed) {
          _retryAfter = _now().add(retryDelay);
          _report('notification_permission_unavailable');
          return;
        }
        _nativeRegistered = true;
      }
      final token = await _platform.currentToken();
      if (!_canBind(owner, generation) ||
          registrationEpoch != _registrationFailureEpoch ||
          !_nativeRegistered) {
        return;
      }
      _retryAfter = null;
      if (token != null) _receiveToken(token);
      if (_wanted != null) await _upload(owner, generation, _wanted!);
    } catch (error) {
      if (!_owns(owner, generation)) return;
      _retryAfter = _now().add(retryDelay);
      _report('registration_unavailable:${error.runtimeType}');
    }
  }

  Future<void> _ensureTransport(APNsPushSession owner, int generation) async {
    if (_transport != null) return;
    final device = await _deviceID();
    if (!_owns(owner, generation)) return;
    _transport = _apiFactory(owner, device);
  }

  Future<void> _handleTap(Map<String, dynamic> payload, APNsPushSession owner,
      int generation) async {
    if (!_owns(owner, generation)) return;
    try {
      await onNotificationTap(payload);
    } catch (error) {
      if (_owns(owner, generation)) {
        _report('notification_tap_unavailable:${error.runtimeType}');
      }
    }
  }

  void _receiveToken(APNsDeviceToken token) {
    final owner = _owner;
    if (owner == null || !_canBind(owner, _generation)) return;
    _wanted = token;
    if (_transport != null && _nativeRegistered) {
      unawaited(_upload(owner, _generation, token));
    }
  }

  Future<void> _upload(
      APNsPushSession owner, int generation, APNsDeviceToken token) {
    final transport = _transport;
    if (!_canBind(owner, generation) ||
        !_nativeRegistered ||
        transport == null ||
        (token == _uploaded && !_rebindRequested && !_bindingExpired) ||
        token == _queued ||
        (_retryAfter != null && _now().isBefore(_retryAfter!))) {
      return _serverOperations;
    }
    final registrationEpoch = _registrationFailureEpoch;
    _queued = token;
    return _server(() async {
      try {
        if (!_canBind(owner, generation) ||
            !_nativeRegistered ||
            registrationEpoch != _registrationFailureEpoch ||
            _wanted != token) {
          return;
        }
        _beginBinding(owner, transport);
        await transport.register(
            token: token.token,
            bundleId: token.bundleID,
            apsEnvironment: token.environment);
        if (!_canBind(owner, generation) ||
            registrationEpoch != _registrationFailureEpoch) {
          return;
        }
        _uploaded = token;
        _uploadedAt = _now();
        _rebindRequested = false;
        _retryAfter = null;
        _report('device_bound');
      } catch (error) {
        if (!_owns(owner, generation) ||
            registrationEpoch != _registrationFailureEpoch) {
          return;
        }
        _retryAfter = _now().add(retryDelay);
        _report('device_binding_unavailable:${error.runtimeType}');
      } finally {
        if (_owns(owner, generation) && _queued == token) _queued = null;
      }
    });
  }

  void _beginBinding(APNsPushSession owner, ApnsTokenApi transport) {
    final scope = (
      endpoint: transport.baseUrl,
      accountID: owner.accountID,
      deviceID: transport.deviceID
    );
    _bindingRevisions[scope] = ++_bindingRevision;
    _completedCleanups.remove(owner);
    for (final cleanup in List<_PendingAPNsCleanup>.of(_pendingCleanups)) {
      if (cleanup.scope == scope) _removeCleanup(cleanup);
    }
  }

  void _retryPendingCleanups() {
    for (final cleanup in List<_PendingAPNsCleanup>.of(_pendingCleanups)) {
      if (cleanup.queued ||
          (cleanup.retryAfter != null &&
              _now().isBefore(cleanup.retryAfter!))) {
        continue;
      }
      cleanup.queued = true;
      unawaited(_server(() async {
        try {
          if (!_pendingCleanups.contains(cleanup)) return;
          cleanup.transport ??= _apiFactory(cleanup.owner, await _deviceID());
          // An unresolved device scope can become known after a new bind was
          // sent. Its captured retirement must never delete that newer binding.
          if (!_pendingCleanups.contains(cleanup) ||
              (_bindingRevisions[cleanup.scope] ?? 0) >
                  cleanup.bindingRevision) {
            _removeCleanup(cleanup);
            return;
          }
          await cleanup.transport!.delete();
          _completedCleanups.add(cleanup.owner);
          _removeCleanup(cleanup);
          _report('device_unbound');
        } catch (error) {
          if (!_pendingCleanups.contains(cleanup)) return;
          cleanup.retryAfter = _now().add(retryDelay);
          _report('device_cleanup_unavailable:${error.runtimeType}');
        } finally {
          cleanup.queued = false;
        }
      }));
    }
  }

  void _removeCleanup(_PendingAPNsCleanup cleanup) {
    _pendingCleanups.remove(cleanup);
    cleanup.transport?.close();
  }

  Future<void> _server(Future<void> Function() action) {
    final operation = _serverOperations.then((_) => action());
    _serverOperations = operation.catchError((Object error) {
      _report('device_cleanup_unavailable:${error.runtimeType}');
    });
    return _serverOperations;
  }

  Future<void> _native(Future<void> Function() action) {
    final operation = _platformOperations.then((_) => action());
    _platformOperations = operation.catchError((Object error) {
      _report('native_registration_unavailable:${error.runtimeType}');
    });
    return _platformOperations;
  }

  void _retireOwner({APNsPushSession? cleanupOwner}) {
    final transport = _transport;
    final retired = _owner ?? cleanupOwner;
    _generation++;
    _owner = null;
    _transport = null;
    _wanted = _uploaded = _queued = null;
    _uploadedAt = _retryAfter = null;
    _bindingDisabled = _disabledUnbound = _rebindRequested = false;
    _nativeRegistered = false;
    _tapsActivated = false;
    if (_initialized) _clearNativeSession();
    if (transport != null || retired != null) {
      if (!_pendingCleanups.any((cleanup) => cleanup.owner == retired)) {
        _pendingCleanups
            .add(_PendingAPNsCleanup(retired!, transport, _bindingRevision));
      } else if (!_pendingCleanups
          .any((cleanup) => identical(cleanup.transport, transport))) {
        transport?.close();
      }
      _retryPendingCleanups();
    }
  }

  void _clearNativeSession() {
    if (_nativeCleared) return;
    _nativeCleared = true;
    unawaited(_native(_platform.unregister));
  }

  /// Invalidates immediately, then waits for old uploads before unbinding.
  /// Repeated route/resume callbacks cannot reactivate this logged-out owner.
  Future<void> endSession({bool logout = true, bool waitForRemote = true}) {
    if (!_supported || _closed) return Future<void>.value();
    if (logout) _clearNativeSession();
    final active = _owner ?? _credentials();
    if (_owner == null &&
        _transport == null &&
        active != null &&
        _blocked == active &&
        (!logout ||
            _completedCleanups.contains(active) ||
            _pendingCleanups.any((cleanup) => cleanup.owner == active))) {
      if (logout) _retryPendingCleanups();
      return _waitForCleanup(waitForRemote: waitForRemote);
    }
    if (active != null) _blocked = active;
    // First cold SDK preparation has never owned a binding. Keep its stored
    // server registration and pending user tap until authentication completes.
    // Explicit logout must still remove that stored device registration.
    _retireOwner(cleanupOwner: logout ? active : null);
    if (logout) _retryPendingCleanups();
    return _waitForCleanup(waitForRemote: waitForRemote);
  }

  Future<void> _waitForCleanup({bool waitForRemote = true}) {
    late final Future<void> ending;
    ending = Future.wait([_serverOperations, _platformOperations])
        .then<void>((_) {})
        .whenComplete(() {
      if (identical(_ending, ending)) _ending = null;
    });
    _ending = ending;
    // Native unregistration must finish before SDK account replacement. Server
    // cleanup retains its captured owner and serialized queue in the background.
    return waitForRemote ? ending : _platformOperations;
  }

  Future<void> dispose() async {
    if (_closed || _disposing) return;
    _disposing = true;
    await endSession();
    _closed = true;
    for (final cleanup in List<_PendingAPNsCleanup>.of(_pendingCleanups)) {
      _removeCleanup(cleanup);
    }
    await _tokenSubscription?.cancel();
    await _tapSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _platform.dispose();
  }
}
