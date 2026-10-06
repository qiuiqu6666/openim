import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart' show Config, DataSp, Logger;
import 'package:uuid/uuid.dart';

import 'data/device_sync_api.dart';
import 'data/device_sync_store.dart';
import 'device_sync_runner.dart';
import 'models/device_sync_preferences.dart';
import 'platform/device_sync_hasher.dart';
import 'platform/device_sync_platform_source.dart';
import 'platform/device_sync_source.dart';

export 'models/device_sync_preferences.dart';

typedef DeviceSyncSession = ({String accountID, String token, String endpoint});
typedef DeviceSyncApiFactory = DeviceSyncApi Function(DeviceSyncSession session,
    DeviceSyncDevice device, bool Function() current);
typedef DeviceSyncStoreFactory = Future<DeviceSyncStore> Function(
    DeviceSyncSession session, DeviceSyncDevice device);

/// Login and views never await media transfers. All resources have one owner.
class DeviceSyncRuntime {
  DeviceSyncRuntime({
    DeviceSyncSession? Function()? currentSession,
    Future<DeviceSyncDevice> Function()? deviceSource,
    DeviceSyncSource Function()? sourceFactory,
    DeviceSyncApiFactory? apiFactory,
    DeviceSyncStoreFactory? storeFactory,
    DateTime Function()? now,
    bool? supported,
    this.quietPeriod = const Duration(seconds: 5),
    this.retryBase = const Duration(minutes: 2),
  })  : _currentSession = currentSession ?? _credentials,
        _deviceSource = deviceSource ?? _device,
        _sourceFactory = sourceFactory ?? DeviceSyncPlatformSource.new,
        _apiFactory = apiFactory ?? _api,
        _storeFactory = storeFactory ?? _store,
        _now = now ?? DateTime.now,
        _supported =
            supported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  static DeviceSyncRuntime? _instance;
  static DeviceSyncRuntime get instance => _instance ??= DeviceSyncRuntime();
  final DeviceSyncSession? Function() _currentSession;
  final Future<DeviceSyncDevice> Function() _deviceSource;
  final DeviceSyncSource Function() _sourceFactory;
  final DeviceSyncApiFactory _apiFactory;
  final DeviceSyncStoreFactory _storeFactory;
  final DateTime Function() _now;
  final bool _supported;
  final Duration quietPeriod, retryBase;
  final _preferences = ValueNotifier(const DeviceSyncPreferences());
  final _status = ValueNotifier(DeviceSyncStatus.inactive);
  ValueListenable<DeviceSyncPreferences> get preferences => _preferences;
  ValueListenable<DeviceSyncStatus> get status => _status;

  bool Function()? _sessionReady, _canRunPhotos;
  DeviceSyncSession? _session;
  DeviceSyncStore? _local;
  DeviceSyncApi? _transport;
  DeviceSyncSource? _source;
  DeviceSyncHasher? _hasher;
  DeviceSyncRunner? _runner;
  Future<void>? _loading;
  Timer? _timer;
  int _generation = 0, _failures = 0, _passRevision = 0;
  bool _foreground = true, _disposed = false;
  bool _passCompleted = false, _running = false;
  bool _preferencesDirty = false, _savingPreferences = false;
  bool _authBlocked = false;
  DateTime? _lastActivity;
  DateTime? _retryAt;
  String _locationID = '';

  static DeviceSyncSession? _credentials() {
    final account = DataSp.userID;
    final token = DataSp.chatToken;
    if (account == null || account.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return (accountID: account, token: token, endpoint: Config.appAuthUrl);
  }

  static Future<DeviceSyncDevice> _device() async {
    var name = Platform.isIOS ? 'iPhone' : 'Android';
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      if (info is AndroidDeviceInfo) {
        name = '${info.manufacturer} ${info.model}';
      }
      if (info is IosDeviceInfo) name = info.name;
    } catch (_) {/* A device description must not block login. */}
    return DeviceSyncDevice(
        deviceID: DataSp.getDeviceID(),
        deviceName: name,
        platform: Platform.isIOS ? 'iOS' : 'Android');
  }

  static DeviceSyncApi _api(DeviceSyncSession session, DeviceSyncDevice device,
          bool Function() current) =>
      DeviceSyncApi(
        device: device,
        chatToken: session.token,
        baseUrl: session.endpoint,
        isCurrent: current,
      );

  static Future<DeviceSyncStore> _store(
          DeviceSyncSession session, DeviceSyncDevice device) =>
      DeviceSyncStore.open(
        accountID: session.accountID,
        endpoint: session.endpoint,
        deviceID: device.deviceID,
      );

  void configure(
      {bool Function()? sessionReady, bool Function()? canRunPhotos}) {
    if (_disposed) return;
    _sessionReady = sessionReady;
    _canRunPhotos = canRunPhotos;
  }

  bool _owns(int generation) =>
      !_disposed &&
      generation == _generation &&
      _session != null &&
      _currentSession() == _session;

  bool get _ready => _foreground && (_sessionReady?.call() ?? true);
  bool get _idle =>
      _ready &&
      (_canRunPhotos?.call() ?? true) &&
      (_lastActivity == null ||
          _now().difference(_lastActivity!) >= quietPeriod);

  Future<void> onSessionReady({bool authenticated = false}) async {
    if (_disposed || !_supported) return;
    final session = _currentSession();
    if (session == null) {
      resetSession();
      return;
    }
    if (_session != session) {
      resetSession();
      _session = session;
      _locationID = 'loc_${const Uuid().v4()}';
      _lastActivity = _now();
    }
    if (_local == null) {
      final remaining = _retryAt?.difference(_now());
      if (remaining != null && remaining > Duration.zero) {
        _schedule(remaining);
        return;
      }
      final currentLoading = _loading;
      if (currentLoading != null) {
        await currentLoading;
      } else {
        final generation = _generation;
        final loading = _load(session, generation);
        _loading = loading;
        try {
          await loading;
        } finally {
          if (identical(_loading, loading)) _loading = null;
        }
      }
    }
    if (_session == session && !_disposed) _schedule(quietPeriod);
  }

  Future<void> _load(DeviceSyncSession session, int generation) async {
    try {
      final device = await _deviceSource();
      if (!_owns(generation)) return;
      final local = await _storeFactory(session, device);
      if (!_owns(generation)) return;
      final source = _sourceFactory();
      final hasher = DeviceSyncHasher();
      final transport = _apiFactory(session, device, () => _owns(generation));
      _local = local;
      _source = source;
      _hasher = hasher;
      _transport = transport;
      _preferences.value = local.preferences;
      _runner = DeviceSyncRunner(
        store: local,
        api: transport,
        source: source,
        hasher: hasher,
        device: device,
        isCurrent: () =>
            _owns(generation) && _idle && _preferences.value.enabled,
        onStatus: (value) {
          if (_owns(generation) &&
              _preferences.value.enabled &&
              !_savingPreferences &&
              _runner?.cancelled != true) {
            _status.value = value;
          }
        },
      );
      _status.value = _preferences.value.enabled
          ? DeviceSyncStatus.idle
          : DeviceSyncStatus.inactive;
    } catch (error) {
      if (!_owns(generation)) return;
      _status.value = DeviceSyncStatus.retrying;
      _retryAt = _now().add(retryBase);
      Logger.print('Device sync preparation unavailable: ${error.runtimeType}',
          onlyConsole: true);
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed || !_foreground || _session == null) return;
    final remaining = _retryAt?.difference(_now());
    if (remaining != null && remaining > delay) delay = remaining;
    _timer = Timer(delay, () => unawaited(_tick()));
  }

  Future<void> _tick() async {
    final generation = _generation;
    final revision = _passRevision;
    try {
      if (_local == null) {
        await onSessionReady();
        return;
      }
      await _runWhenIdle();
    } catch (error) {
      if (!_owns(generation) || revision != _passRevision) return;
      // Preference persistence failures must not leak into the IM zone.
      _status.value = _preferences.value.enabled
          ? DeviceSyncStatus.retrying
          : DeviceSyncStatus.inactive;
      _retryAt = _now().add(retryBase);
      _schedule(retryBase);
      Logger.print('Device sync preferences deferred: ${error.runtimeType}',
          onlyConsole: true);
    }
  }

  Future<void> _runWhenIdle() async {
    final generation = _generation;
    if (!_owns(generation) || _local == null || _runner == null) return;
    if (_savingPreferences) return;
    if (_preferencesDirty) await _persistPreferences(_passRevision);
    if (!_owns(generation)) return;
    if (_authBlocked) {
      _status.value = DeviceSyncStatus.inactive;
      return;
    }
    if (!_preferences.value.enabled || _passCompleted) {
      if (!_preferences.value.enabled) {
        _status.value = DeviceSyncStatus.inactive;
      }
      return;
    }
    if (!_idle || _running) {
      _status.value = DeviceSyncStatus.paused;
      _schedule(quietPeriod);
      return;
    }
    final revision = _passRevision;
    _running = true;
    final runner = _runner!;
    try {
      await runner.run(_preferences.value, locationClientID: _locationID);
      if (!_owns(generation) || revision != _passRevision) return;
      _failures = 0;
      _retryAt = null;
      _passCompleted = _status.value != DeviceSyncStatus.paused;
      if (_passCompleted &&
          _status.value != DeviceSyncStatus.waitingPermission) {
        _status.value = DeviceSyncStatus.idle;
      }
    } catch (error) {
      if (!_owns(generation) || revision != _passRevision) return;
      if (runner.cancelled || !_idle) {
        _status.value = _preferences.value.enabled
            ? DeviceSyncStatus.paused
            : DeviceSyncStatus.inactive;
        if (_preferences.value.enabled) _schedule(quietPeriod);
      } else if (error is DeviceSyncException && error.isAuthError) {
        // Stop this feature until credentials change; never clear IM login.
        _passCompleted = true;
        _authBlocked = true;
        _status.value = DeviceSyncStatus.inactive;
      } else {
        _failures++;
        _status.value = DeviceSyncStatus.retrying;
        final milliseconds = math.min(900000,
            retryBase.inMilliseconds * (1 << math.min(_failures - 1, 4)));
        _retryAt = _now().add(Duration(milliseconds: milliseconds));
        _schedule(Duration(milliseconds: milliseconds));
        Logger.print('Device sync deferred: ${error.runtimeType}',
            onlyConsole: true);
      }
    } finally {
      if (_owns(generation)) {
        _running = false;
        if (!_savingPreferences &&
            _preferences.value.enabled &&
            !_passCompleted &&
            _status.value == DeviceSyncStatus.paused) {
          _schedule(quietPeriod);
        }
      }
    }
  }

  Future<void> setPreferences(
      {bool? photos, bool? videos, bool? location, bool? wifiOnly}) async {
    final generation = _generation;
    final local = _local;
    if (local == null || !_owns(generation)) return;
    final updated = _preferences.value.copyWith(
        photos: photos, videos: videos, location: location, wifiOnly: wifiOnly);
    _timer?.cancel();
    _runner?.cancel();
    if (_preferences.value.location && !updated.location) {
      _runner?.discardLocation();
    }
    final revision = ++_passRevision;
    _retryAt = null;
    // Publish the choice before awaiting disk IO. A canceled older pass must
    // never restart using the previous enabled configuration.
    _preferences.value = updated;
    _preferencesDirty = true;
    _passCompleted = false;
    _status.value =
        updated.enabled ? DeviceSyncStatus.paused : DeviceSyncStatus.inactive;
    try {
      await _persistPreferences(revision);
    } catch (_) {
      if (_owns(generation) && revision == _passRevision) {
        _retryAt = _now().add(retryBase);
        _schedule(retryBase);
      }
      rethrow;
    }
    if (_owns(generation) && revision == _passRevision && updated.enabled) {
      _schedule(quietPeriod);
    }
  }

  Future<void> _persistPreferences(int revision) async {
    final generation = _generation;
    final local = _local;
    final updated = _preferences.value;
    bool current() =>
        _owns(generation) &&
        revision == _passRevision &&
        identical(_local, local);
    if (local == null || !current()) return;
    _savingPreferences = true;
    try {
      await local.savePreferences(updated, isCurrent: current);
      if (!current()) return;
      if (!updated.location) await local.clearLocations(isCurrent: current);
      if (current()) _preferencesDirty = false;
    } finally {
      if (current()) _savingPreferences = false;
    }
  }

  void markUserActivity() {
    if (_disposed) return;
    _lastActivity = _now();
    _runner?.cancel();
    if (_preferences.value.enabled) _schedule(quietPeriod);
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    final changed = _foreground != foreground;
    _foreground = foreground;
    if (!foreground) {
      _timer?.cancel();
      _runner?.cancel();
      _status.value = _preferences.value.enabled
          ? DeviceSyncStatus.paused
          : DeviceSyncStatus.inactive;
    } else if (changed) {
      _passCompleted = false;
      markUserActivity();
      unawaited(onSessionReady());
    }
  }

  void resetSession() {
    if (_disposed) return;
    _generation++;
    _passRevision++;
    _timer?.cancel();
    _runner?.cancel();
    _transport?.close(force: true);
    _source?.dispose();
    _hasher?.dispose();
    _local = null;
    _transport = null;
    _source = null;
    _hasher = null;
    _runner = null;
    _session = null;
    _loading = null;
    _running = false;
    _passCompleted = false;
    _failures = 0;
    _retryAt = null;
    _preferencesDirty = false;
    _savingPreferences = false;
    _authBlocked = false;
    _preferences.value = const DeviceSyncPreferences();
    _status.value = DeviceSyncStatus.inactive;
  }

  void dispose() {
    if (_disposed) return;
    resetSession();
    _disposed = true;
    _preferences.dispose();
    _status.dispose();
    if (identical(_instance, this)) _instance = null;
  }
}
