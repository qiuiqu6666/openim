import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:openim/core/device_sync/data/device_sync_api.dart';
import 'package:openim/core/device_sync/data/device_sync_store.dart';
import 'package:openim/core/device_sync/device_sync_runner.dart';
import 'package:openim/core/device_sync/models/device_sync_preferences.dart';
import 'package:openim/core/device_sync/platform/device_sync_hasher.dart';
import 'package:openim/core/device_sync/platform/device_sync_source.dart';

const _device = DeviceSyncDevice(
    deviceID: 'device-1', deviceName: 'Fixture phone', platform: 'Android');
const _hash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const _asset = DeviceSyncAsset(
    id: 'library/asset-1',
    fingerprint: 'version-1',
    kind: 'image',
    name: 'fixture.jpg',
    contentType: 'image/jpeg',
    capturedAt: 0);
const _photos =
    DeviceSyncPreferences(accountID: 'owner', photos: true, wifiOnly: false);
const _location =
    DeviceSyncPreferences(accountID: 'owner', location: true, wifiOnly: false);

DeviceSyncMedia _media() => const DeviceSyncMedia(
    localID: 'album_fixture',
    sha256: _hash,
    size: 3,
    kind: DeviceSyncMediaKind.image);
DeviceSyncLocation _point(String id) => DeviceSyncLocation(
    clientID: id,
    latitude: 31.2,
    longitude: 121.4,
    accuracy: 15,
    recordedAt: DateTime.now().millisecondsSinceEpoch);

class _Source implements DeviceSyncSource {
  _Source(this.file);
  final File file;
  final List<DeviceSyncAsset> assets = const [_asset];
  int scans = 0, opens = 0, cleanups = 0, locates = 0;
  FutureOr<DeviceSyncLocation?> Function(String)? locationResponse;
  @override
  Stream<List<DeviceSyncAsset>> pages({required bool includeVideos}) async* {
    scans++;
    yield assets;
  }

  @override
  Future<DeviceSyncFile?> openFile(DeviceSyncAsset asset,
      {required CancelToken cancelToken}) async {
    opens++;
    return DeviceSyncFile(
        file: file,
        onDispose: () async {
          cleanups++;
        });
  }

  @override
  Future<DeviceSyncLocation?> locate(String clientID,
      {required CancelToken cancelToken}) async {
    locates++;
    return await locationResponse?.call(clientID);
  }

  @override
  Future<bool> hasUnmeteredNetwork() async => true;
  @override
  void dispose() {}
}

class _Hasher extends DeviceSyncHasher {
  int calls = 0;
  @override
  Future<String> hash(File file, {required CancelToken cancelToken}) async {
    calls++;
    return (await crypto.sha256.bind(file.openRead()).first).toString();
  }
}

class _Api extends DeviceSyncApi {
  _Api()
      : super(
            device: _device,
            chatToken: 'fixture',
            baseUrl: 'https://chat.test',
            isCurrent: () => true);
  final probes = <DeviceSyncMedia>[];
  final tickets = <DeviceSyncMedia>[];
  final uploads = <int>[];
  final finishes = <DeviceSyncMedia>[];
  final points = <List<DeviceSyncLocation>>[];
  FutureOr<DeviceSyncMediaState> Function(DeviceSyncMedia, int)? probeResponse;
  DeviceSyncUploadTicket Function(DeviceSyncMedia, int)? ticketResponse;
  DeviceSyncFinishResult Function(DeviceSyncMedia, int)? finishResponse;
  FutureOr<void> Function(List<DeviceSyncLocation>, int)? locationResponse;

  @override
  Future<List<DeviceSyncProbeResult>> probe(List<DeviceSyncMedia> items,
      {CancelToken? cancelToken}) async {
    final media = items.single;
    probes.add(media);
    final state = await (probeResponse?.call(media, probes.length) ??
        DeviceSyncMediaState.done);
    return [
      DeviceSyncProbeResult.fromJson({
        'localID': media.localID,
        'state': state.name,
        'received': state == DeviceSyncMediaState.done ? media.size : 0,
        'reset': false,
        'mode': '',
        'partSize': 0,
        'doneParts': []
      }, media)
    ];
  }

  @override
  Future<DeviceSyncUploadTicket> ticket(DeviceSyncMedia media,
      {CancelToken? cancelToken}) async {
    tickets.add(media);
    return ticketResponse!(media, tickets.length);
  }

  @override
  Future<void> putPart(
      File file, DeviceSyncUploadTicket ticket, DeviceSyncUploadPart part,
      {CancelToken? cancelToken}) async {
    expect(await file.exists(), isTrue);
    uploads.add(part.partNumber);
  }

  @override
  Future<DeviceSyncFinishResult> finish(DeviceSyncMedia media,
      {CancelToken? cancelToken}) async {
    finishes.add(media);
    return finishResponse!(media, finishes.length);
  }

  @override
  Future<DeviceSyncLocationsResult> locations(
      List<DeviceSyncLocation> locations,
      {CancelToken? cancelToken}) async {
    points.add(List.of(locations));
    await locationResponse?.call(locations, points.length);
    final unique = locations.map((point) => point.clientID).toSet().length;
    return DeviceSyncLocationsResult.fromJson(
        {'stored': unique, 'duplicated': 0}, unique);
  }
}

void main() {
  late Directory directory;
  late File file;
  late DeviceSyncStore store;
  late _Source source;
  late _Api api;
  late _Hasher hasher;
  final statuses = <DeviceSyncStatus>[];

  DeviceSyncRunner runner({bool Function()? current}) => DeviceSyncRunner(
      store: store,
      api: api,
      source: source,
      hasher: hasher,
      device: _device,
      isCurrent: current ?? () => true,
      onStatus: statuses.add);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('device-sync-runner-');
    Hive.init(directory.path);
    store = await DeviceSyncStore.open(
        accountID: 'owner',
        endpoint: 'https://chat.test',
        deviceID: _device.deviceID);
    file = await File('${directory.path}/fixture.jpg')
        .writeAsBytes([97, 98, 99], flush: true);
    source = _Source(file);
    api = _Api();
    hasher = _Hasher();
    statuses.clear();
  });
  tearDown(() async {
    api.close();
    hasher.dispose();
    await Hive.close();
    // Only this test's newly created directory and its fixtures are removed.
    expect(directory.parent.path, Directory.systemTemp.path);
    await directory.delete(recursive: true);
  });

  test('saved disabled preferences never invoke a source or API method',
      () async {
    await runner().run(const DeviceSyncPreferences(accountID: 'owner'),
        locationClientID: 'loc-login');
    expect([source.scans, source.opens, source.locates, hasher.calls],
        [0, 0, 0, 0]);
    expect(api.probes, isEmpty);
    expect(api.points, isEmpty);
    expect(store.pendingLocations, isEmpty);
  });

  test('a completed unchanged asset is skipped before export hash and probe',
      () async {
    await store.saveMedia(_asset.id, _asset.fingerprint, _media(), done: true);
    await runner().run(_photos, locationClientID: 'loc-login');
    expect(source.scans, 1);
    expect([source.opens, hasher.calls], [0, 0]);
    expect(api.probes, isEmpty);
    expect(await file.readAsBytes(), [97, 98, 99]);
  });

  test('cancel and late probe failure never mark done and release export once',
      () async {
    final reply = Completer<DeviceSyncMediaState>(),
        reached = Completer<void>();
    api.probeResponse = (_, __) {
      reached.complete();
      return reply.future;
    };
    final task = runner();
    final pending = task.run(_photos, locationClientID: 'loc-login');
    final rejected = expectLater(pending, throwsA(isA<DeviceSyncException>()));
    await reached.future;
    task.cancel();
    reply.completeError(
        const DeviceSyncException('NETWORK_ERROR', 'Fixture failure'));
    await rejected;
    expect(store.isCompleted(_asset.id, _asset.fingerprint), isFalse);
    expect(store.prepared(_asset.id, _asset.fingerprint), isNotNull);
    expect(source.cleanups, 1);
    expect(await file.exists(), isTrue,
        reason: 'A borrowed library original is preserved.');
  });

  test('conflict ID is stable across a failure and the following retry',
      () async {
    api.probeResponse = (_, index) {
      if (index == 1) return DeviceSyncMediaState.conflict;
      if (index == 2) {
        throw const DeviceSyncException('NETWORK_ERROR', 'Fixture failure');
      }
      return DeviceSyncMediaState.done;
    };
    final task = runner();
    await expectLater(task.run(_photos, locationClientID: 'loc-login'),
        throwsA(isA<DeviceSyncException>()));
    final retryID = api.probes[1].localID;
    expect(retryID, isNot(api.probes.first.localID));
    expect(store.prepared(_asset.id, _asset.fingerprint)!.localID, retryID);
    await task.run(_photos, locationClientID: 'loc-login');
    expect(api.probes.last.localID, retryID);
    expect(api.probes.last.sha256, _hash);
    expect(store.isCompleted(_asset.id, _asset.fingerprint), isTrue);
    expect(source.cleanups, 2);
  });

  test(
      'multipart retickets only after non-done finish and skips completed parts',
      () async {
    final writer = await file.open(mode: FileMode.write);
    await writer.truncate(deviceSyncPartSize + 3);
    await writer.close();
    api.probeResponse = (_, __) => DeviceSyncMediaState.upload;
    api.ticketResponse = (media, index) => DeviceSyncUploadTicket.fromJson({
          'mode': 'multipart',
          'state': 'resume',
          'url': '',
          'uploadID': 'upload-fixture',
          'size': media.size,
          'contentType': media.contentType,
          'partSize': deviceSyncPartSize,
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
          'received': index == 1 ? deviceSyncPartSize : media.size,
          'doneParts': index == 1 ? [1] : [1, 2],
          'parts': index == 1
              ? [
                  {
                    'partNumber': 2,
                    'offset': deviceSyncPartSize,
                    'size': 3,
                    'url':
                        'https://99chat.oss-cn-hongkong.aliyuncs.com/fixture?signature=test'
                  }
                ]
              : [],
        }, media, now: DateTime.now());
    api.finishResponse = (media, index) => DeviceSyncFinishResult.fromJson({
          'state': index == 1 ? 'resume' : 'done',
          'size': media.size,
          'received': media.size,
        }, media);
    await runner().run(_photos, locationClientID: 'loc-login');
    expect(api.tickets, hasLength(2));
    expect(api.finishes, hasLength(2));
    expect(api.uploads, [2]);
    expect(api.tickets.map((media) => media.localID).toSet(), hasLength(1));
    expect(store.isCompleted(_asset.id, _asset.fingerprint), isTrue);
    expect(source.cleanups, 1);
  });

  test(
      'location retry retains its persisted ID and coordinates without another fix',
      () async {
    source.locationResponse = _point;
    api.locationResponse = (_, index) {
      if (index == 1) {
        throw const DeviceSyncException('NETWORK_ERROR', 'Fixture failure');
      }
    };
    final task = runner();
    await expectLater(task.run(_location, locationClientID: 'loc-login'),
        throwsA(isA<DeviceSyncException>()));
    final pending = store.pendingLocations.single;
    expect(pending.clientID, 'loc-login');
    await task.run(_location, locationClientID: 'loc-login');
    expect(source.locates, 1);
    expect(api.points, hasLength(2));
    expect(api.points.last.single.clientID, pending.clientID);
    expect(api.points.last.single.recordedAt, pending.recordedAt);
    expect(api.points.last.single.latitude, pending.latitude);
    expect(store.pendingLocations, isEmpty);
  });

  test('a no-fix result is attempted once per login and never uploads a point',
      () async {
    final task = runner();
    await task.run(_location, locationClientID: 'loc-login');
    await task.run(_location, locationClientID: 'loc-login');
    expect(source.locates, 1);
    expect(api.points, isEmpty);
    expect(store.pendingLocations, isEmpty);
    expect(statuses.last, DeviceSyncStatus.idle);
  });

  test('GPS timeout also skips an older queued location for this login',
      () async {
    await store.enqueueLocation(_point('loc-previous-login'));
    final task = runner();
    await task.run(_location, locationClientID: 'loc-timeout-login');
    await task.run(_location, locationClientID: 'loc-timeout-login');
    expect(source.locates, 1);
    expect(api.points, isEmpty);
    expect(store.pendingLocations.single.clientID, 'loc-previous-login');
  });

  test(
      'stored preferences done assets and queued points are isolated by account endpoint and device',
      () async {
    await store.savePreferences(_photos);
    await store.saveMedia(_asset.id, _asset.fingerprint, _media(), done: true);
    await store.enqueueLocation(_point('loc-persisted'));
    for (final scope in [
      (
        account: 'another-owner',
        endpoint: 'https://chat.test',
        device: 'device-1'
      ),
      (account: 'owner', endpoint: 'https://another.test', device: 'device-1'),
      (account: 'owner', endpoint: 'https://chat.test', device: 'device-2'),
    ]) {
      final other = await DeviceSyncStore.open(
          accountID: scope.account,
          endpoint: scope.endpoint,
          deviceID: scope.device);
      expect(other.preferences.accountID, scope.account);
      expect(other.preferences.photos, isTrue);
      expect(other.preferences.location, isTrue);
      expect(other.preferences.videos, isTrue);
      expect(other.preferences.wifiOnly, isTrue);
      expect(other.isCompleted(_asset.id, _asset.fingerprint), isFalse);
      expect(other.pendingLocations, isEmpty);
    }
    expect(
        () => store
            .savePreferences(const DeviceSyncPreferences(accountID: 'other')),
        throwsA(isA<StateError>()));
  });

  test(
      'store reopen retains pending IDs and location clear preserves media and preferences',
      () async {
    await store.savePreferences(_photos);
    await store.saveMedia(_asset.id, _asset.fingerprint, _media(), done: true);
    final point = _point('loc-persisted');
    await store.enqueueLocation(point);
    await Hive.close();
    store = await DeviceSyncStore.open(
        accountID: 'owner',
        endpoint: 'https://chat.test',
        deviceID: _device.deviceID);
    expect(store.pendingLocations.single.clientID, point.clientID);
    expect(store.pendingLocations.single.recordedAt, point.recordedAt);
    await store.clearLocations();
    expect(store.pendingLocations, isEmpty);
    expect(store.preferences.photos, isTrue);
    expect(store.preferences.location, isFalse);
    expect(store.preferences.wifiOnly, isFalse);
    expect(store.isCompleted(_asset.id, _asset.fingerprint), isTrue);
    expect(store.isCompleted(_asset.id, 'updated-version'), isFalse);
  });

  test(
      'retired queued writes cannot replace or delete the next login state in the same store',
      () async {
    await store.savePreferences(_location);
    await store.saveMedia(_asset.id, 'new-version', _media(), done: true);
    await store.enqueueLocation(_point('loc-new-login'));
    var oldLoginCurrent = true;
    final writes = [
      store.savePreferences(_photos, isCurrent: () => oldLoginCurrent),
      store.saveMedia(_asset.id, 'old-version', _media(),
          done: true, isCurrent: () => oldLoginCurrent),
      store.enqueueLocation(_point('loc-old-login'),
          isCurrent: () => oldLoginCurrent),
      store.clearLocations(isCurrent: () => oldLoginCurrent),
    ];
    final rejected = writes
        .map((write) => expectLater(write, throwsA(isA<StateError>())))
        .toList();
    // Retire before queued work reaches Hive, then write the current owner's choice.
    oldLoginCurrent = false;
    await store.savePreferences(_location);
    await Future.wait(rejected);
    expect(store.preferences.location, isTrue);
    expect(store.preferences.photos, isFalse);
    expect(store.isCompleted(_asset.id, 'new-version'), isTrue);
    expect(store.isCompleted(_asset.id, 'old-version'), isFalse);
    expect(store.pendingLocations.map((point) => point.clientID),
        ['loc-new-login']);
  });
}
