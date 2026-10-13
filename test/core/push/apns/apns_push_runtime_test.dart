import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/push/apns/apns_platform.dart';
import 'package:openim/core/push/apns/apns_push_runtime.dart';
import 'package:openim/core/push/apns/apns_token_api.dart';

const _firstToken = APNsDeviceToken(
  token: 'aabbccdd',
  bundleID: 'vip.99chat.ios',
  environment: 'development',
);
const _nextToken = APNsDeviceToken(
  token: '11223344',
  bundleID: 'vip.99chat.ios',
  environment: 'development',
);

APNsPushSession _session(String account) => (
      accountID: account,
      token: 'chat-token-$account',
      endpoint: 'https://chat.example.test',
      sessionKey: 'session-$account',
    );

Future<void> _drain() async {
  // These tests use no real network or timers. Yield an event turn so stream
  // callbacks and the runtime's chained operations can reach their barriers.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void _releaseAtTearDown(Completer<void> barrier) {
  addTearDown(() {
    if (!barrier.isCompleted) barrier.complete();
  });
}

class _Platform implements APNsPlatform {
  final _tokens = StreamController<APNsDeviceToken>.broadcast(sync: true);
  final _taps = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final _errors = StreamController<int>.broadcast(sync: true);
  APNsDeviceToken? token = _firstToken;
  Map<String, dynamic>? pendingTap;
  Completer<void>? initializeBarrier,
      registerBarrier,
      currentTokenBarrier,
      unregisterBarrier;
  bool allowed = true;
  bool acceptsTaps = true;
  int initializationFailures = 0;
  int initializes = 0,
      activations = 0,
      registers = 0,
      unregisters = 0,
      disposals = 0;

  @override
  Stream<APNsDeviceToken> get tokens => _tokens.stream;
  @override
  Stream<Map<String, dynamic>> get notificationTaps => _taps.stream;
  @override
  Stream<int> get registrationErrors => _errors.stream;

  void emit(APNsDeviceToken value) {
    token = value;
    _tokens.add(value);
  }

  void tap(Map<String, dynamic> value) {
    if (acceptsTaps) _taps.add(value);
  }

  void registrationFailed(int code) => _errors.add(code);

  @override
  Future<void> initialize() async {
    initializes++;
    if (initializationFailures > 0) {
      initializationFailures--;
      throw StateError('simulated native failure');
    }
    await initializeBarrier?.future;
    final pending = pendingTap;
    pendingTap = null;
    if (pending != null) tap(pending);
  }

  @override
  Future<void> activateNotificationTaps() async {
    activations++;
    acceptsTaps = true;
  }

  @override
  Future<bool> register() async {
    registers++;
    await registerBarrier?.future;
    return allowed;
  }

  @override
  Future<APNsDeviceToken?> currentToken() async {
    final cached = token;
    await currentTokenBarrier?.future;
    return cached;
  }

  @override
  Future<void> unregister() async {
    unregisters++;
    acceptsTaps = false;
    pendingTap = null;
    await unregisterBarrier?.future;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await _tokens.close();
    await _taps.close();
    await _errors.close();
  }
}

class _Api extends ApnsTokenApi {
  _Api(this.owner, this.events)
      : super(
          baseUrl: owner.endpoint,
          imToken: owner.token,
          userID: owner.accountID,
          deviceID: 'device-1',
        );

  final APNsPushSession owner;
  final List<String> events;
  final registrations = <APNsDeviceToken>[];
  Completer<void>? registerBarrier, deleteBarrier;
  int failures = 0, deleteFailures = 0, deletes = 0, closes = 0;

  @override
  Future<void> register({
    required String token,
    required String bundleId,
    required String apsEnvironment,
    CancelToken? cancelToken,
  }) async {
    registrations.add(APNsDeviceToken(
      token: token,
      bundleID: bundleId,
      environment: apsEnvironment,
    ));
    events.add('register:start:${owner.accountID}:$token');
    await registerBarrier?.future;
    if (failures > 0) {
      failures--;
      throw StateError('simulated provider failure');
    }
    events.add('register:end:${owner.accountID}:$token');
  }

  @override
  Future<void> delete({CancelToken? cancelToken}) async {
    deletes++;
    events.add('delete:start:${owner.accountID}');
    await deleteBarrier?.future;
    if (deleteFailures > 0) {
      deleteFailures--;
      throw StateError('simulated provider failure');
    }
    events.add('delete:end:${owner.accountID}');
  }

  @override
  void close({bool force = true}) {
    closes++;
    events.add('close:${owner.accountID}');
    super.close(force: force);
  }
}

class _Fixture {
  _Fixture({
    bool supported = true,
    void Function(_Api)? configureApi,
  }) {
    runtime = APNsPushRuntime(
      supported: supported,
      platform: platform,
      sessionReady: () => ready,
      notificationsEnabled: (_) => notificationsEnabled,
      currentSession: () => session,
      deviceID: () async {
        devices++;
        await deviceBarrier?.future;
        return 'device-1';
      },
      apiFactory: (owner, device) {
        expect(device, 'device-1');
        final api = _Api(owner, events);
        configureApi?.call(api);
        apis.add(api);
        return api;
      },
      reportStatus: reports.add,
      onNotificationTap: (value) async => taps.add(value),
      now: () => now,
      retryDelay: const Duration(seconds: 30),
    );
  }

  final platform = _Platform();
  final apis = <_Api>[];
  final events = <String>[], reports = <String>[];
  final taps = <Map<String, dynamic>>[];
  late final APNsPushRuntime runtime;
  APNsPushSession? session = _session('alice');
  DateTime now = DateTime.utc(2026, 10, 11);
  bool ready = true, notificationsEnabled = true;
  Completer<void>? deviceBarrier;
  int devices = 0;

  _Api get api => apis.last;

  Future<void> dispose() => runtime.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final remoteFails in [false, true]) {
    test('local cleanup waits for native but not remote / failure=$remoteFails',
        () async {
      final fixture = _Fixture();
      final remote = Completer<void>(), native = Completer<void>();
      addTearDown(fixture.dispose);
      _releaseAtTearDown(remote);
      _releaseAtTearDown(native);
      await fixture.runtime.onSessionReady(authenticated: true);
      final oldApi = fixture.api;
      oldApi.deleteBarrier = remote;
      oldApi.deleteFailures = remoteFails ? 1 : 0;
      fixture.platform.unregisterBarrier = native;
      var localDone = false, allDone = false;
      final local = fixture.runtime.endSession(waitForRemote: false)
          .then((_) => localDone = true);
      final all = fixture.runtime.endSession().then((_) => allDone = true);
      await _drain();
      expect(localDone, isFalse);
      native.complete();
      await local;
      expect(allDone, isFalse);
      expect(fixture.platform.acceptsTaps, isFalse);
      fixture.session = _session('bob');
      remote.complete();
      await all;
      expect(oldApi.owner.accountID, 'alice');
      expect(fixture.events, isNot(contains('delete:start:bob')));
    });
  }

  test('unsupported platforms do not install Apple listeners or bind',
      () async {
    final fixture = _Fixture(supported: false);
    addTearDown(fixture.dispose);

    await fixture.runtime.onSessionReady(authenticated: true);

    expect(fixture.platform.initializes, 0);
    expect(fixture.apis, isEmpty);
  });

  test('requires both a ready IM session and captured IM credentials',
      () async {
    final fixture = _Fixture()..ready = false;
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.ready = true;
    fixture.session = null;
    await fixture.runtime.onSessionReady(authenticated: true);

    expect(fixture.platform.initializes, 0);
    expect(fixture.apis, isEmpty);
  });

  test(
      'cold-start authentication unblocks credentials before navigation is ready',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.platform.pendingTap = {'accountID': 'alice', 'marker': 'cold-tap'};
    await fixture.runtime.endSession(logout: false);
    await fixture.runtime.endSession(logout: false);
    expect(fixture.apis, isEmpty);
    expect(fixture.devices, 0);
    expect(fixture.platform.unregisters, 0);
    expect(fixture.platform.pendingTap?['marker'], 'cold-tap');

    fixture.ready = false;
    await fixture.runtime.onSessionReady(authenticated: true);
    expect(fixture.platform.initializes, 0);
    fixture.ready = true;
    await fixture.runtime.onSessionReady();

    expect(fixture.apis, hasLength(1));
    expect(fixture.api.owner, fixture.session);
    expect(fixture.api.registrations, [_firstToken]);
    await _drain();
    expect(fixture.taps, [
      {'accountID': 'alice', 'marker': 'cold-tap'}
    ]);
  });

  test('concurrent and repeated session-ready callbacks bind once', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await Future.wait([
      fixture.runtime.onSessionReady(authenticated: true),
      fixture.runtime.onSessionReady(),
      fixture.runtime.onSessionReady(),
    ]);
    await fixture.runtime.onSessionReady();
    fixture.platform.emit(_firstToken);
    await _drain();

    expect(fixture.platform.initializes, 1);
    expect(fixture.platform.registers, 1);
    expect(fixture.devices, 1);
    expect(fixture.apis, hasLength(1));
    expect(fixture.api.registrations, [_firstToken]);
    expect(fixture.api.owner, fixture.session);
  });

  test('token refresh uploads the new token and deduplicates callbacks',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);

    fixture.platform.emit(_nextToken);
    fixture.platform.emit(_nextToken);
    await _drain();
    await fixture.runtime.onSessionReady();

    expect(fixture.api.registrations, [_firstToken, _nextToken]);
  });

  test('foreground renews a cached token and coalesces concurrent resumes',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    final renewal = Completer<void>();
    _releaseAtTearDown(renewal);
    fixture.api.registerBarrier = renewal;
    fixture.now = fixture.now.add(const Duration(minutes: 10));

    final resumed = Future.wait([
      fixture.runtime.onForeground(),
      fixture.runtime.onForeground(),
      fixture.runtime.onSessionReady(),
    ]);
    await _drain();
    expect(fixture.api.registrations, [_firstToken, _firstToken]);
    renewal.complete();
    await resumed;
    await fixture.runtime.onSessionReady();
    fixture.platform.emit(_firstToken);
    await _drain();

    expect(fixture.api.registrations, [_firstToken, _firstToken]);
    expect(fixture.platform.registers, 1);
  });

  test('foreground renewal survives a temporarily unready SDK', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.ready = false;

    await fixture.runtime.onForeground();
    expect(fixture.api.registrations, [_firstToken]);
    fixture.ready = true;
    await fixture.runtime.onSessionReady();

    expect(fixture.api.registrations, [_firstToken, _firstToken]);
  });

  test('session callbacks renew at 24 hours and successful ack resets age',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.now = fixture.now.add(const Duration(hours: 23, minutes: 59));
    await fixture.runtime.onSessionReady();
    expect(fixture.api.registrations, [_firstToken]);

    fixture.now = fixture.now.add(const Duration(minutes: 1));
    fixture.api.failures = 1;
    await fixture.runtime.onSessionReady();
    expect(fixture.api.registrations, [_firstToken, _firstToken]);
    expect(fixture.reports.where((status) => status == 'device_bound'),
        hasLength(1));
    fixture.now = fixture.now.add(const Duration(seconds: 29));
    await fixture.runtime.onSessionReady();
    expect(fixture.api.registrations, hasLength(2));
    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.runtime.onSessionReady();
    expect(fixture.api.registrations, hasLength(3));

    fixture.now = fixture.now.add(const Duration(hours: 23, minutes: 59));
    await fixture.runtime.onSessionReady();
    expect(fixture.api.registrations, hasLength(3));
    expect(fixture.reports.where((status) => status == 'device_bound'),
        hasLength(2));
  });

  test('closed notification preference cleans only this device before opt-in',
      () async {
    final fixture = _Fixture()..notificationsEnabled = false;
    addTearDown(fixture.dispose);
    fixture.platform.pendingTap = {'accountID': 'alice', 'marker': 'cold-tap'};
    await fixture.runtime.onSessionReady(authenticated: true);
    await fixture.runtime.onSessionReady();
    await fixture.runtime.onPreferencesChanged('alice');

    expect(fixture.platform.initializes, 1);
    expect(fixture.platform.registers, 0);
    expect(fixture.apis, hasLength(1));
    expect(fixture.api.deletes, 1);
    expect(fixture.api.registrations, isEmpty);
    await _drain();
    expect(fixture.taps, [
      {'accountID': 'alice', 'marker': 'cold-tap'}
    ]);
    fixture.notificationsEnabled = true;
    await fixture.runtime.onPreferencesChanged('alice');

    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, [_firstToken]);
    expect(fixture.api.deletes, 1);
  });

  test('closing notifications fences an upload then deletes before restoring',
      () async {
    final upload = Completer<void>();
    final fixture =
        _Fixture(configureApi: (api) => api.registerBarrier = upload);
    addTearDown(fixture.dispose);
    _releaseAtTearDown(upload);
    final preparing = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    fixture.notificationsEnabled = false;
    final closing = fixture.runtime.onPreferencesChanged('alice');
    fixture.platform.emit(_nextToken);
    final foreground = fixture.runtime.onForeground();
    await _drain();
    expect(fixture.platform.unregisters, 0);
    expect(fixture.api.deletes, 0);
    expect(fixture.api.registrations, [_firstToken]);

    upload.complete();
    await Future.wait([preparing, closing, foreground]);
    expect(fixture.api.deletes, 1);
    expect(fixture.reports, isNot(contains('device_bound')));
    fixture.notificationsEnabled = true;
    await fixture.runtime.onPreferencesChanged('alice');

    expect(fixture.api.registrations, [_firstToken, _nextToken]);
    expect(
        fixture.events.indexOf('delete:end:alice'),
        lessThan(fixture.events
            .indexOf('register:start:alice:${_nextToken.token}')));
  });

  test('closing notifications unbinds even while the SDK is reconnecting',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.ready = false;
    fixture.notificationsEnabled = false;

    await fixture.runtime.onPreferencesChanged('alice');
    expect(fixture.api.deletes, 1);
    fixture.notificationsEnabled = true;
    await fixture.runtime.onPreferencesChanged('alice');
    expect(fixture.api.registrations, [_firstToken]);
    fixture.ready = true;
    await fixture.runtime.onSessionReady();

    expect(fixture.api.registrations, [_firstToken, _firstToken]);
  });

  test('failed preference deletion retries without registering a token',
      () async {
    final fixture = _Fixture(configureApi: (api) => api.deleteFailures = 1)
      ..notificationsEnabled = false;
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.now = fixture.now.add(const Duration(seconds: 29));
    await fixture.runtime.onSessionReady();
    expect(fixture.api.deletes, 1);
    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.runtime.onSessionReady();
    await fixture.runtime.onPreferencesChanged('alice');

    expect(fixture.api.deletes, 2);
    expect(fixture.api.registrations, isEmpty);
    expect(fixture.platform.registers, 0);
  });

  test('disabled login after logout restores clicks without requesting pushes',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    await fixture.runtime.endSession();
    expect(fixture.platform.acceptsTaps, isFalse);
    fixture.notificationsEnabled = false;

    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.platform.tap({'accountID': 'alice', 'marker': 'after-login'});
    await _drain();

    expect(fixture.platform.initializes, 1);
    expect(fixture.platform.activations, 2);
    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, isEmpty);
    expect(fixture.api.deletes, 1);
    expect(fixture.taps, [
      {'accountID': 'alice', 'marker': 'after-login'}
    ]);
  });

  test(
      'disabled cleanup can succeed while the native tap bridge is unavailable',
      () async {
    final fixture = _Fixture()..notificationsEnabled = false;
    addTearDown(fixture.dispose);
    fixture.platform.initializationFailures = 1;

    await fixture.runtime.onSessionReady(authenticated: true);
    expect(fixture.api.deletes, 1);
    expect(fixture.platform.registers, 0);
    await fixture.runtime.onSessionReady();
    fixture.platform.tap({'accountID': 'alice', 'marker': 'retry-tap'});
    await _drain();

    expect(fixture.platform.initializes, 2);
    expect(fixture.api.deletes, 1);
    expect(fixture.taps, [
      {'accountID': 'alice', 'marker': 'retry-tap'}
    ]);
  });

  test(
      'logout before readiness deletes the captured old binding and clears taps',
      () async {
    final fixture = _Fixture()..ready = false;
    addTearDown(fixture.dispose);
    fixture.platform.pendingTap = {'accountID': 'alice', 'marker': 'stale'};
    final logout = fixture.runtime.endSession();
    fixture.session = null;
    await logout;

    expect(fixture.api.owner.accountID, 'alice');
    expect(fixture.api.deletes, 1);
    expect(fixture.api.closes, 1);
    expect(fixture.api.registrations, isEmpty);
    expect(fixture.platform.initializes, 0);
    expect(fixture.platform.unregisters, 1);
    expect(fixture.platform.pendingTap, isNull);
  });

  test('failed logout cleanup stays pending until a foreground retry succeeds',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    final oldApi = fixture.api;
    oldApi.deleteFailures = 1;

    await fixture.runtime.endSession();
    fixture.session = null;
    fixture.ready = false;
    expect(oldApi.deletes, 1);
    expect(oldApi.closes, 0);
    expect(fixture.reports, isNot(contains('device_unbound')));
    await fixture.runtime.endSession();
    await fixture.runtime.onSessionReady();
    fixture.now = fixture.now.add(const Duration(seconds: 29));
    await fixture.runtime.onForeground();
    await _drain();
    expect(oldApi.deletes, 1);

    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.runtime.onForeground();
    await _drain();
    expect(oldApi.deletes, 2);
    expect(oldApi.closes, 1);
    expect(fixture.apis, hasLength(1));
    expect(fixture.reports.where((status) => status == 'device_unbound'),
        hasLength(1));
    await fixture.runtime.endSession();
    await fixture.runtime.onForeground();
    expect(oldApi.deletes, 2);
  });

  test(
      'account switch retries failed cleanup with the captured old IM identity',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    final oldApi = fixture.api;
    final oldOwner = fixture.session;
    oldApi.deleteFailures = 1;

    fixture.session = _session('bob');
    await fixture.runtime.onSessionReady(authenticated: true);
    final newApi = fixture.api;
    expect(oldApi.deletes, 1);
    expect(oldApi.closes, 0);
    expect(newApi.registrations, [_firstToken]);

    fixture.now = fixture.now.add(const Duration(seconds: 30));
    await Future.wait([
      fixture.runtime.onSessionReady(),
      fixture.runtime.onForeground(),
    ]);
    expect(oldApi.deletes, 2);
    expect(oldApi.owner, oldOwner);
    expect(oldApi.imToken, oldOwner!.token);
    expect(oldApi.userID, 'alice');
    expect(oldApi.deviceID, 'device-1');
    expect(oldApi.closes, 1);
    expect(newApi.deletes, 0);
    expect(fixture.apis, hasLength(2));
    expect(
        fixture.events.lastIndexOf('delete:end:alice'),
        lessThan(fixture.events
            .lastIndexOf('register:start:bob:${_firstToken.token}')));
  });

  test(
      'same-device new binding supersedes failed cleanup without late deletion',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    final oldApi = fixture.api;
    oldApi.deleteFailures = 1;
    await fixture.runtime.endSession();
    final previous = fixture.session!;
    fixture.session = (
      accountID: previous.accountID,
      token: 'new-im-token-alice',
      endpoint: previous.endpoint,
      sessionKey: 'new-session-alice',
    );

    await fixture.runtime.onSessionReady(authenticated: true);
    final newApi = fixture.api;
    expect(oldApi.deletes, 1);
    expect(oldApi.closes, 1);
    expect(newApi.registrations, [_firstToken]);
    // Superseding a failed deletion is not an acknowledgement of that DELETE.
    expect(fixture.reports, isNot(contains('device_unbound')));
    fixture.now = fixture.now.add(const Duration(minutes: 1));
    await fixture.runtime.onForeground();
    await fixture.runtime.onSessionReady();
    expect(oldApi.deletes, 1);
    expect(newApi.deletes, 0);
    expect(newApi.registrations, [_firstToken, _firstToken]);
  });

  test('another account retry cannot erase a completed logout acknowledgement',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    final alice = fixture.api;
    alice.deleteFailures = 1;
    fixture.session = _session('bob');
    await fixture.runtime.onSessionReady(authenticated: true);
    final bob = fixture.api;
    await fixture.runtime.endSession();
    expect(bob.deletes, 1);

    fixture.ready = false;
    fixture.now = fixture.now.add(const Duration(seconds: 30));
    await fixture.runtime.onForeground();
    await _drain();
    expect(alice.deletes, 2);
    await fixture.runtime.endSession();
    expect(bob.deletes, 1);
    expect(fixture.apis, hasLength(2));
  });

  test('cold SDK preparation preserves persisted binding without networking',
      () async {
    final fixture = _Fixture(configureApi: (api) => api.deleteFailures = 1)
      ..ready = false;
    addTearDown(fixture.dispose);
    fixture.platform.pendingTap = {'accountID': 'alice', 'marker': 'cold'};

    await fixture.runtime.endSession(logout: false);
    await fixture.runtime.endSession(logout: false);
    fixture.now = fixture.now.add(const Duration(minutes: 1));
    await fixture.runtime.onForeground();
    await _drain();
    expect(fixture.apis, isEmpty);
    expect(fixture.devices, 0);
    expect(fixture.events, isEmpty);
    expect(fixture.platform.unregisters, 0);
    expect(fixture.platform.pendingTap?['marker'], 'cold');
  });

  test('logout while device identity is pending cleans before completing',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final device = Completer<void>();
    _releaseAtTearDown(device);
    fixture.deviceBarrier = device;
    final preparing = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    expect(fixture.apis, isEmpty);
    final logout = fixture.runtime.endSession();
    fixture.session = null;
    await _drain();
    expect(fixture.apis, isEmpty);

    device.complete();
    await Future.wait([preparing, logout]);
    expect(fixture.apis, hasLength(1));
    expect(fixture.api.owner.accountID, 'alice');
    expect(fixture.api.deletes, 1);
    expect(fixture.api.closes, 1);
    expect(fixture.platform.registers, 0);
  });

  test(
      'explicit logout escalates cold preparation and waits for native clearing',
      () async {
    final deletion = Completer<void>(), unregister = Completer<void>();
    final fixture =
        _Fixture(configureApi: (api) => api.deleteBarrier = deletion);
    addTearDown(fixture.dispose);
    _releaseAtTearDown(deletion);
    _releaseAtTearDown(unregister);
    fixture.platform.unregisterBarrier = unregister;
    fixture.platform.pendingTap = {'accountID': 'alice', 'marker': 'cold'};
    final preparation = fixture.runtime.endSession(logout: false);
    await _drain();
    expect(fixture.apis, isEmpty);
    expect(fixture.devices, 0);
    expect(fixture.platform.unregisters, 0);
    expect(fixture.platform.pendingTap?['marker'], 'cold');
    var fullyEnded = false;
    final logout = fixture.runtime.endSession().then((_) => fullyEnded = true);
    final repeated = fixture.runtime.endSession();
    await _drain();
    expect(fixture.platform.unregisters, 1);
    expect(fixture.platform.pendingTap, isNull);
    expect(fixture.api.deletes, 1);

    deletion.complete();
    await preparation;
    expect(fullyEnded, isFalse);
    unregister.complete();
    await Future.wait([logout, repeated]);
    expect(fullyEnded, isTrue);
    expect(fixture.api.deletes, 1);
    expect(fixture.platform.unregisters, 1);
  });

  test(
      'same-account login waits for explicit orphan cleanup before registering',
      () async {
    final deletion = Completer<void>();
    var created = 0;
    final fixture = _Fixture(configureApi: (api) {
      if (created++ == 0) api.deleteBarrier = deletion;
    });
    addTearDown(fixture.dispose);
    _releaseAtTearDown(deletion);
    final preparation = fixture.runtime.endSession();
    await _drain();
    final login = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    expect(fixture.apis, hasLength(2));
    expect(fixture.api.registrations, isEmpty);

    deletion.complete();
    await Future.wait([preparation, login]);
    expect(fixture.apis.first.deletes, 1);
    expect(fixture.api.registrations, [_firstToken]);
    expect(
        fixture.events.indexOf('delete:end:alice'),
        lessThan(fixture.events
            .indexOf('register:start:alice:${_firstToken.token}')));
  });

  test('a changed APNs environment is a different registration', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    const production = APNsDeviceToken(
      token: 'aabbccdd',
      bundleID: 'vip.99chat.ios',
      environment: 'production',
    );

    fixture.platform.emit(production);
    await _drain();

    expect(fixture.api.registrations, [_firstToken, production]);
  });

  test('switching account during preparation still prepares the new owner',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final initialize = Completer<void>();
    _releaseAtTearDown(initialize);
    fixture.platform.initializeBarrier = initialize;
    final alice = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    fixture.session = _session('bob');
    final bob = fixture.runtime.onSessionReady(authenticated: true);

    initialize.complete();
    await Future.wait([alice, bob]);
    await _drain();

    expect(fixture.apis, hasLength(2));
    expect(fixture.apis.first.owner.accountID, 'alice');
    expect(fixture.apis.first.deletes, 1);
    expect(fixture.apis.first.registrations, isEmpty);
    expect(fixture.api.owner.accountID, 'bob');
    expect(fixture.api.registrations, [_firstToken]);
  });

  test('logout waits for an in-flight POST before DELETE and closing',
      () async {
    final upload = Completer<void>();
    final fixture =
        _Fixture(configureApi: (api) => api.registerBarrier = upload);
    addTearDown(fixture.dispose);
    _releaseAtTearDown(upload);
    final ready = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    expect(fixture.api.registrations, [_firstToken]);

    final logout = fixture.runtime.endSession();
    await _drain();
    expect(fixture.api.deletes, 0);
    expect(fixture.api.closes, 0);
    fixture.platform.emit(_nextToken);
    await fixture.runtime.onSessionReady();
    upload.complete();
    await Future.wait([ready, logout]);

    expect(fixture.events, [
      'register:start:alice:${_firstToken.token}',
      'register:end:alice:${_firstToken.token}',
      'delete:start:alice',
      'delete:end:alice',
      'close:alice',
    ]);
    expect(fixture.api.registrations, [_firstToken]);
    expect(fixture.api.closes, 1);
  });

  test('new account POST waits until the previous account DELETE finishes',
      () async {
    final deletion = Completer<void>();
    final fixture = _Fixture(configureApi: (api) {
      if (api.owner.accountID == 'alice') api.deleteBarrier = deletion;
    });
    addTearDown(fixture.dispose);
    _releaseAtTearDown(deletion);
    await fixture.runtime.onSessionReady(authenticated: true);
    final oldApi = fixture.api;
    final logout = fixture.runtime.endSession();
    await _drain();
    expect(oldApi.deletes, 1);

    fixture.session = _session('bob');
    final login = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    expect(
        fixture.events.any((event) => event.startsWith('register:start:bob:')),
        isFalse);

    deletion.complete();
    await Future.wait([logout, login]);

    expect(fixture.api.owner.accountID, 'bob');
    expect(fixture.api.registrations, [_firstToken]);
    expect(
        fixture.events.indexOf('delete:end:alice'),
        lessThan(
          fixture.events.indexOf('register:start:bob:${_firstToken.token}'),
        ));
    expect(oldApi.closes, 1);
  });

  test('account switch without logout also retires the old binding first',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    final oldApi = fixture.api;

    fixture.session = _session('bob');
    await fixture.runtime.onSessionReady(authenticated: true);

    expect(oldApi.deletes, 1);
    expect(oldApi.closes, 1);
    expect(fixture.api.owner.accountID, 'bob');
    expect(
        fixture.events.indexOf('delete:end:alice'),
        lessThan(
          fixture.events.indexOf('register:start:bob:${_firstToken.token}'),
        ));
  });

  test('logout blocks stale callbacks and ordinary resume until explicit login',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    await fixture.runtime.endSession();
    final previous = List<String>.of(fixture.events);

    fixture.platform.emit(_nextToken);
    fixture.platform.tap({'accountID': 'alice'});
    await fixture.runtime.onSessionReady();
    await _drain();

    expect(fixture.events, previous);
    expect(fixture.apis, hasLength(1));
    expect(fixture.taps, isEmpty);

    await fixture.runtime.onSessionReady(authenticated: true);
    expect(fixture.apis, hasLength(2));
    expect(fixture.api.registrations, [_nextToken]);
  });

  test('failed upload waits for retry time and then binds the latest token',
      () async {
    final fixture = _Fixture(configureApi: (api) => api.failures = 1);
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    expect(fixture.api.registrations, [_firstToken]);
    expect(fixture.reports, contains('device_binding_unavailable:StateError'));

    fixture.platform.emit(_nextToken);
    fixture.now = fixture.now.add(const Duration(seconds: 29));
    await fixture.runtime.onSessionReady();
    await _drain();
    expect(fixture.api.registrations, [_firstToken]);

    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.runtime.onSessionReady();
    await fixture.runtime.onSessionReady();
    expect(fixture.api.registrations, [_firstToken, _nextToken]);
    expect(fixture.reports, contains('device_bound'));
  });

  test('permission denial retries after the delay without uploading early',
      () async {
    final fixture = _Fixture();
    fixture.platform.allowed = false;
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.platform.allowed = true;
    await fixture.runtime.onSessionReady();

    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, isEmpty);
    fixture.now = fixture.now.add(const Duration(seconds: 30));
    await fixture.runtime.onSessionReady();

    expect(fixture.platform.registers, 2);
    expect(fixture.api.registrations, [_firstToken]);
  });

  test('native registration errors wait before registering again', () async {
    final fixture = _Fixture();
    fixture.platform.token = null;
    addTearDown(fixture.dispose);
    await fixture.runtime.onSessionReady(authenticated: true);
    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, isEmpty);

    fixture.platform.registrationFailed(3010);
    fixture.platform.emit(_nextToken);
    await fixture.runtime.onSessionReady();
    await _drain();
    expect(fixture.reports, contains('native_registration_failed:3010'));
    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, isEmpty);

    fixture.now = fixture.now.add(const Duration(seconds: 30));
    await fixture.runtime.onSessionReady();
    expect(fixture.platform.registers, 2);
    expect(fixture.api.registrations, [_nextToken]);
  });

  test(
      'native error while reading a cached token prevents POST and early retry',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final cachedToken = Completer<void>();
    _releaseAtTearDown(cachedToken);
    fixture.platform.currentTokenBarrier = cachedToken;
    final preparing = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, isEmpty);

    fixture.platform.registrationFailed(3010);
    cachedToken.complete();
    await preparing;
    expect(fixture.reports, contains('native_registration_failed:3010'));
    expect(fixture.api.registrations, isEmpty);

    fixture.now = fixture.now.add(const Duration(seconds: 29));
    await fixture.runtime.onSessionReady();
    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, isEmpty);

    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.runtime.onSessionReady();
    expect(fixture.platform.registers, 2);
    expect(fixture.api.registrations, [_firstToken]);
  });

  test('native error during register is not overwritten by allowed response',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final registering = Completer<void>();
    _releaseAtTearDown(registering);
    fixture.platform.registerBarrier = registering;
    final preparing = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();
    expect(fixture.platform.registers, 1);

    fixture.platform.registrationFailed(3010);
    registering.complete();
    await preparing;
    expect(fixture.reports, contains('native_registration_failed:3010'));
    expect(fixture.api.registrations, isEmpty);

    fixture.now = fixture.now.add(const Duration(seconds: 29));
    await fixture.runtime.onSessionReady();
    expect(fixture.platform.registers, 1);
    expect(fixture.api.registrations, isEmpty);

    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.runtime.onSessionReady();
    expect(fixture.platform.registers, 2);
    expect(fixture.api.registrations, [_firstToken]);
  });

  test('a failed native initialization can be retried', () async {
    const channel = MethodChannel('apns_runtime_platform_retry');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var installs = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'install' && ++installs == 1) {
        throw PlatformException(code: 'temporarily_unavailable');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final platform = MethodChannelAPNsPlatform(channel: channel);
    addTearDown(platform.dispose);

    await expectLater(platform.initialize(), throwsA(isA<PlatformException>()));
    await platform.initialize();

    expect(installs, 2);
  });

  test('logout during native preparation cannot upload its late result',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final initialize = Completer<void>();
    _releaseAtTearDown(initialize);
    fixture.platform.initializeBarrier = initialize;
    final ready = fixture.runtime.onSessionReady(authenticated: true);
    await _drain();

    await fixture.runtime.endSession();
    initialize.complete();
    await ready;
    await fixture.runtime.onSessionReady();

    expect(fixture.platform.registers, 0);
    expect(fixture.apis, hasLength(1));
    expect(fixture.api.deletes, 1);
    expect(fixture.api.closes, 1);
    expect(fixture.api.registrations, isEmpty);
  });

  test('dispose rejects new authenticated login while DELETE is pending',
      () async {
    final deletion = Completer<void>();
    final fixture =
        _Fixture(configureApi: (api) => api.deleteBarrier = deletion);
    addTearDown(fixture.dispose);
    _releaseAtTearDown(deletion);
    await fixture.runtime.onSessionReady(authenticated: true);
    final disposing = fixture.runtime.dispose();
    await _drain();
    expect(fixture.api.deletes, 1);
    fixture.session = _session('bob');
    final lateLogin = fixture.runtime.onSessionReady(authenticated: true);
    fixture.platform.emit(_nextToken);
    fixture.platform.tap({'accountID': 'bob'});
    await _drain();

    expect(fixture.apis, hasLength(1));
    expect(fixture.taps, isEmpty);
    deletion.complete();
    await Future.wait([disposing, lateLogin]);
    expect(fixture.api.closes, 1);
    expect(fixture.platform.disposals, 1);
  });

  test('dispose closes listeners and remains idempotent', () async {
    final fixture = _Fixture();
    await fixture.runtime.onSessionReady(authenticated: true);
    fixture.platform.tap({'accountID': 'alice', 'marker': 'before-dispose'});
    await _drain();
    expect(fixture.taps, hasLength(1));

    await fixture.runtime.dispose();
    await fixture.runtime.dispose();
    await fixture.runtime.onSessionReady(authenticated: true);

    expect(fixture.platform.disposals, 1);
    expect(fixture.api.deletes, 1);
    expect(fixture.api.closes, 1);
    expect(fixture.apis, hasLength(1));
  });
}
