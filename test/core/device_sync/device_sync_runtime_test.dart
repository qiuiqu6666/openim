import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:openim/core/device_sync/data/device_sync_api.dart';
import 'package:openim/core/device_sync/data/device_sync_store.dart';
import 'package:openim/core/device_sync/device_sync_runtime.dart';
import 'package:openim/core/device_sync/platform/device_sync_source.dart';

const _device = DeviceSyncDevice(
    deviceID: 'runtime-device',
    deviceName: 'Fixture phone',
    platform: 'Android');

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Runtime did not reach the expected fixture state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

DeviceSyncLocation _point(String id) => DeviceSyncLocation(
    clientID: id,
    latitude: 31.2,
    longitude: 121.4,
    accuracy: 10,
    recordedAt: DateTime.now().millisecondsSinceEpoch);

class _Source implements DeviceSyncSource {
  int scans = 0, locates = 0, opens = 0, disposed = 0;
  final locationIDs = <String>[];
  final videoScopes = <bool>[];
  @override
  Stream<List<DeviceSyncAsset>> pages({required bool includeVideos}) async* {
    scans++;
    videoScopes.add(includeVideos);
    yield [];
  }

  @override
  Future<DeviceSyncFile?> openFile(DeviceSyncAsset asset,
      {required CancelToken cancelToken}) async {
    opens++;
    return null;
  }

  @override
  Future<DeviceSyncLocation?> locate(String id,
      {required CancelToken cancelToken}) async {
    locates++;
    locationIDs.add(id);
    return _point(id);
  }

  @override
  Future<bool> hasUnmeteredNetwork() async => true;
  @override
  void dispose() => disposed++;
}

class _Api extends DeviceSyncApi {
  _Api(bool Function() current)
      : super(
            device: _device,
            chatToken: 'fixture',
            baseUrl: 'https://chat.test',
            isCurrent: current);
  final requests = <List<DeviceSyncLocation>>[];
  final requestTimes = <DateTime>[];
  Future<void> Function()? response;
  @override
  Future<DeviceSyncLocationsResult> locations(List<DeviceSyncLocation> points,
      {CancelToken? cancelToken}) async {
    requests.add(List.of(points));
    requestTimes.add(DateTime.now());
    await response?.call();
    final count = points.map((point) => point.clientID).toSet().length;
    return DeviceSyncLocationsResult.fromJson(
        {'stored': count, 'duplicated': 0}, count);
  }
}

/// Delays only a preference write; all data and queued writes use real Hive.
class _DelayedStore implements DeviceSyncStore {
  _DelayedStore(this.delegate);
  final DeviceSyncStore delegate;
  Completer<void>? preferenceWrite;
  @override
  String get accountID => delegate.accountID;
  @override
  DeviceSyncPreferences get preferences => delegate.preferences;
  @override
  List<DeviceSyncLocation> get pendingLocations => delegate.pendingLocations;
  @override
  bool isCompleted(String id, String fingerprint) =>
      delegate.isCompleted(id, fingerprint);
  @override
  DeviceSyncMedia? prepared(String id, String fingerprint) =>
      delegate.prepared(id, fingerprint);
  @override
  Future<void> savePreferences(DeviceSyncPreferences value,
      {bool Function()? isCurrent}) async {
    await preferenceWrite?.future;
    await delegate.savePreferences(value, isCurrent: isCurrent);
  }

  @override
  Future<void> saveMedia(String id, String fingerprint, DeviceSyncMedia media,
          {bool done = false, bool Function()? isCurrent}) =>
      delegate.saveMedia(id, fingerprint, media,
          done: done, isCurrent: isCurrent);
  @override
  Future<void> enqueueLocation(DeviceSyncLocation point,
          {bool Function()? isCurrent}) =>
      delegate.enqueueLocation(point, isCurrent: isCurrent);
  @override
  Future<void> removeLocations(Iterable<String> ids,
          {bool Function()? isCurrent}) =>
      delegate.removeLocations(ids, isCurrent: isCurrent);
  @override
  Future<void> clearLocations({bool Function()? isCurrent}) =>
      delegate.clearLocations(isCurrent: isCurrent);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late DeviceSyncStore store;
  DeviceSyncRuntime? runtime;
  DeviceSyncSession? session;
  final sources = <_Source>[];
  final apis = <_Api>[];

  Future<DeviceSyncRuntime> create({
    DeviceSyncStore? runtimeStore,
    Duration retryBase = const Duration(seconds: 1),
  }) async {
    runtime = DeviceSyncRuntime(
        currentSession: () => session,
        deviceSource: () async => _device,
        storeFactory: (_, __) async => runtimeStore ?? store,
        sourceFactory: () {
          final source = _Source();
          sources.add(source);
          return source;
        },
        apiFactory: (_, __, current) {
          final api = _Api(current);
          apis.add(api);
          return api;
        },
        supported: true,
        quietPeriod: const Duration(milliseconds: 5),
        retryBase: retryBase);
    return runtime!;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('device-sync-runtime-');
    Hive.init(directory.path);
    store = await DeviceSyncStore.open(
        accountID: 'owner',
        endpoint: 'https://chat.test',
        deviceID: _device.deviceID);
    session = (
      accountID: 'owner',
      token: 'fixture-token',
      endpoint: 'https://chat.test'
    );
    runtime = null;
    sources.clear();
    apis.clear();
  });
  tearDown(() async {
    runtime?.dispose();
    await Hive.close();
    expect(directory.parent.path, Directory.systemTemp.path);
    await directory.delete(recursive: true);
  });

  test(
      'a new login starts photo video and location sync without a confirmation',
      () async {
    final task = await create();
    expect(task.preferences.value.enabled, isFalse);
    await task.onSessionReady(authenticated: true);
    expect(task.preferences.value.photos, isTrue);
    expect(task.preferences.value.location, isTrue);
    expect(task.preferences.value.videos, isTrue);
    expect(task.preferences.value.wifiOnly, isTrue);
    await _until(() =>
        sources.single.scans == 1 &&
        apis.single.requests.length == 1 &&
        store.pendingLocations.isEmpty);
    expect([sources.single.locates, sources.single.scans, sources.single.opens],
        [1, 1, 0]);
    expect(sources.single.videoScopes, [true]);
    expect(apis.single.requests.single.single.clientID,
        sources.single.locationIDs.single);
    expect(store.pendingLocations, isEmpty);
  });

  test('saved video opt-out survives foreground and a new login', () async {
    await store.savePreferences(
        DeviceSyncPreferences.fromJson('owner', null).copyWith(videos: false));
    final task = await create();
    await task.onSessionReady(authenticated: true);
    await _until(() => sources.single.scans == 1);
    expect(sources.single.videoScopes, [false]);
    task.setForeground(false);
    task.setForeground(true);
    await task.onSessionReady(authenticated: true);
    expect(task.preferences.value.videos, isFalse);
    session = (
      accountID: 'owner',
      token: 'new-login-token',
      endpoint: 'https://chat.test'
    );
    await task.onSessionReady(authenticated: true);
    await _until(() => sources.length == 2 && sources.last.scans == 1);
    expect(sources.last.videoScopes, [false]);
    expect(task.preferences.value.photos, isTrue);
    expect(task.preferences.value.videos, isFalse);
    expect(store.preferences.videos, isFalse);
  });

  test('without a login default sync stays inactive and creates no sources',
      () async {
    session = null;
    final task = await create();
    await task.onSessionReady();
    task.setForeground(false);
    task.setForeground(true);
    task.markUserActivity();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(task.preferences.value.enabled, isFalse);
    expect(task.status.value, DeviceSyncStatus.inactive);
    expect(sources, isEmpty);
    expect(apis, isEmpty);
  });

  test('default sync waits until the session is ready and chat is idle',
      () async {
    var ready = false, idle = false;
    final task = await create();
    task.configure(sessionReady: () => ready, canRunPhotos: () => idle);
    await task.onSessionReady(authenticated: true);
    await _until(() => task.status.value == DeviceSyncStatus.paused);
    expect(task.preferences.value.enabled, isTrue);
    expect([sources.single.locates, sources.single.scans], [0, 0]);
    expect(apis.single.requests, isEmpty);
    ready = true;
    await task.onSessionReady(authenticated: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect([sources.single.locates, sources.single.scans], [0, 0]);
    expect(apis.single.requests, isEmpty);
    idle = true;
    await task.onSessionReady(authenticated: true);
    await _until(() =>
        sources.single.scans == 1 &&
        apis.single.requests.length == 1 &&
        store.pendingLocations.isEmpty);
    expect(sources.single.locates, 1);
  });

  test(
      'same login and foreground restoration keep one fix while a new login has a new ID',
      () async {
    await store.savePreferences(
        const DeviceSyncPreferences(accountID: 'owner', location: true));
    final task = await create();
    await task.onSessionReady(authenticated: true);
    await _until(() =>
        apis.single.requests.length == 1 && store.pendingLocations.isEmpty);
    final firstID = sources.single.locationIDs.single;
    await task.onSessionReady(authenticated: true);
    task.setForeground(false);
    task.setForeground(true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sources.single.locates, 1);
    expect(apis.single.requests, hasLength(1));
    expect(task.status.value, DeviceSyncStatus.idle);
    session = (
      accountID: 'owner',
      token: 'new-login-token',
      endpoint: 'https://chat.test'
    );
    await task.onSessionReady(authenticated: true);
    await _until(() =>
        sources.length == 2 &&
        sources.last.locates == 1 &&
        apis.last.requests.length == 1 &&
        store.pendingLocations.isEmpty);
    expect(sources.last.locationIDs.single, isNot(firstID));
    expect(sources.first.disposed, 1);
  });

  test(
      'turning location off clears persisted retry data and a late failure cannot reactivate it',
      () async {
    await store.savePreferences(
        const DeviceSyncPreferences(accountID: 'owner', location: true));
    final failed = Completer<void>(), reached = Completer<void>();
    final task = await create();
    await task.onSessionReady(authenticated: true);
    apis.single.response = () {
      reached.complete();
      return failed.future;
    };
    await reached.future;
    expect(store.pendingLocations, hasLength(1));
    await task.setPreferences(location: false);
    expect(store.pendingLocations, isEmpty);
    expect(task.preferences.value.enabled, isFalse);
    failed.completeError(
        const DeviceSyncException('NETWORK_ERROR', 'Late fixture failure'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(task.status.value, DeviceSyncStatus.inactive);
    expect(store.pendingLocations, isEmpty);
    expect(sources.single.locates, 1);
    expect(apis.single.requests, hasLength(1));
  });

  test(
      'turning location off takes effect before a slow disk write and stays off after a late failure',
      () async {
    await store.savePreferences(
        const DeviceSyncPreferences(accountID: 'owner', location: true));
    final delayedStore = _DelayedStore(store);
    final failed = Completer<void>(), reached = Completer<void>();
    final diskWrite = Completer<void>();
    final task = await create(runtimeStore: delayedStore);
    await task.onSessionReady(authenticated: true);
    apis.single.response = () {
      reached.complete();
      return failed.future;
    };
    await reached.future;
    delayedStore.preferenceWrite = diskWrite;
    final closing = task.setPreferences(location: false);
    try {
      expect(task.preferences.value.enabled, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(task.status.value, DeviceSyncStatus.inactive);
      expect(sources.single.locates, 1);
      expect(apis.single.requests, hasLength(1));
      failed.completeError(
          const DeviceSyncException('NETWORK_ERROR', 'Late fixture failure'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(task.status.value, DeviceSyncStatus.inactive);
      expect(apis.single.requests, hasLength(1));
      diskWrite.complete();
      await closing;
      expect(store.preferences.enabled, isFalse);
      expect(store.pendingLocations, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(task.status.value, DeviceSyncStatus.inactive);
      expect(sources.single.locates, 1);
      expect(apis.single.requests, hasLength(1));
    } finally {
      if (!failed.isCompleted) failed.complete();
      if (!diskWrite.isCompleted) diskWrite.complete();
      await closing;
    }
  });

  test(
      'disabling default sync before the first pass persists without collection',
      () async {
    var idle = false;
    final task = await create();
    task.configure(canRunPhotos: () => idle);
    await task.onSessionReady(authenticated: true);
    expect(task.preferences.value.enabled, isTrue);
    await task.setPreferences(
        photos: false, videos: false, location: false, wifiOnly: false);
    idle = true;
    await task.onSessionReady(authenticated: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(task.preferences.value.enabled, isFalse);
    expect(task.preferences.value.wifiOnly, isFalse);
    expect(store.preferences.enabled, isFalse);
    expect(store.preferences.wifiOnly, isFalse);
    expect(task.status.value, DeviceSyncStatus.inactive);
    expect([sources.single.locates, sources.single.scans], [0, 0]);
    expect(apis.single.requests, isEmpty);
    expect(store.pendingLocations, isEmpty);
  });

  test('saved off choices survive repeated login foreground and a new login',
      () async {
    await store.savePreferences(
        const DeviceSyncPreferences(accountID: 'owner', wifiOnly: false));
    final task = await create();
    await task.onSessionReady(authenticated: true);
    await task.onSessionReady(authenticated: true);
    task.setForeground(false);
    task.setForeground(true);
    task.markUserActivity();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(task.preferences.value.enabled, isFalse);
    expect(task.status.value, DeviceSyncStatus.inactive);
    expect([sources.single.locates, sources.single.scans], [0, 0]);
    expect(apis.single.requests, isEmpty);
    session = (
      accountID: 'owner',
      token: 'new-login-token',
      endpoint: 'https://chat.test'
    );
    await task.onSessionReady(authenticated: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sources, hasLength(2));
    expect(sources.first.disposed, 1);
    expect(task.preferences.value.enabled, isFalse);
    expect(task.preferences.value.wifiOnly, isFalse);
    expect(store.preferences.enabled, isFalse);
    expect(task.status.value, DeviceSyncStatus.inactive);
    expect([sources.last.locates, sources.last.scans], [0, 0]);
    expect(apis.last.requests, isEmpty);
  });

  test(
      'an invalid token remains blocked across foreground and resumes with a new token',
      () async {
    await store.savePreferences(
        const DeviceSyncPreferences(accountID: 'owner', location: true));
    final task = await create();
    await task.onSessionReady(authenticated: true);
    apis.single.response = () async {
      throw const DeviceSyncException('AUTH_INVALID', 'Fixture token expired');
    };
    await _until(() =>
        apis.single.requests.length == 1 &&
        task.status.value == DeviceSyncStatus.inactive);
    final originalToken = session!.token;
    final firstLocationID = sources.single.locationIDs.single;
    for (var turn = 0; turn < 3; turn++) {
      task.setForeground(false);
      task.setForeground(true);
      task.markUserActivity();
      await task.onSessionReady(authenticated: true);
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    expect(apis.single.requests, hasLength(1));
    expect(sources.single.locates, 1);
    expect(task.status.value, DeviceSyncStatus.inactive);
    expect(session!.token, originalToken, reason: 'Sync never logs IM out.');
    session = (
      accountID: 'owner',
      token: 'refreshed-token',
      endpoint: 'https://chat.test'
    );
    await task.onSessionReady(authenticated: true);
    await _until(() =>
        apis.length == 2 &&
        apis.last.requests.length == 1 &&
        store.pendingLocations.isEmpty);
    expect(task.status.value, DeviceSyncStatus.idle);
    expect(sources.last.locates, 1);
    expect(sources.last.locationIDs.single, isNot(firstLocationID));
    expect(sources.first.disposed, 1);
    expect(apis.first.requests, hasLength(1));
  });

  test(
      'activity and session-ready events cannot shorten a network retry deadline',
      () async {
    await store.savePreferences(
        const DeviceSyncPreferences(accountID: 'owner', location: true));
    const retryBase = Duration(milliseconds: 300);
    final task = await create(retryBase: retryBase);
    await task.onSessionReady(authenticated: true);
    apis.single.response = () async {
      if (apis.single.requests.length == 1) {
        throw const DeviceSyncException('NETWORK_ERROR', 'Fixture unavailable');
      }
    };
    await _until(() => task.status.value == DeviceSyncStatus.retrying);
    final point = store.pendingLocations.single;
    for (var event = 0; event < 4; event++) {
      task.markUserActivity();
      await task.onSessionReady(authenticated: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(apis.single.requests, hasLength(1),
          reason: 'Chat activity must retain the existing retry deadline.');
    }
    await _until(() =>
        apis.single.requests.length == 2 && store.pendingLocations.isEmpty);
    expect(
        apis.single.requestTimes.last
            .difference(apis.single.requestTimes.first),
        greaterThanOrEqualTo(retryBase));
    expect(sources.single.locates, 1);
    expect(apis.single.requests.last.single.clientID, point.clientID);
    expect(apis.single.requests.last.single.recordedAt, point.recordedAt);
    expect(task.status.value, DeviceSyncStatus.idle);
  });
}
