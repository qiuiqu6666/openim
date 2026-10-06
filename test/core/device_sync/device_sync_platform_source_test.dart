import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:openim/core/device_sync/platform/device_sync_platform_source.dart';
import 'package:openim/core/device_sync/platform/device_sync_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const photos = MethodChannel('com.fluttercandies/photo_manager');
  const originals = MethodChannel('openim_device_sync_originals');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late GeolocatorPlatform originalLocationPlatform;
  late _Locations locations;
  late DeviceSyncPlatformSource source;
  late List<MethodCall> photoCalls;
  late List<MethodCall> exportCalls;

  setUp(() {
    originalLocationPlatform = GeolocatorPlatform.instance;
    locations = _Locations();
    GeolocatorPlatform.instance = locations;
    source = DeviceSyncPlatformSource(platform: TargetPlatform.iOS);
    photoCalls = [];
    exportCalls = [];
    messenger.setMockMethodCallHandler(photos, (call) async {
      photoCalls.add(call);
      if (call.method == 'getPermissionState') return 3; // authorized
      throw StateError('Unexpected photo method ${call.method}');
    });
    messenger.setMockMethodCallHandler(originals, (call) async {
      exportCalls.add(call);
      if (call.method == 'open') return {'path': '/synthetic/owned.data'};
      return null;
    });
  });

  tearDown(() async {
    source.dispose();
    if (!locations.points.isClosed) await locations.points.close();
    GeolocatorPlatform.instance = originalLocationPlatform;
    messenger.setMockMethodCallHandler(photos, null);
    messenger.setMockMethodCallHandler(originals, null);
  });

  const asset = DeviceSyncAsset(
      id: 'original-id',
      fingerprint: 'metadata',
      kind: 'image',
      name: 'IMG.heic',
      contentType: 'image/heic',
      capturedAt: 1);

  test('denied media never opens picker or original export', () async {
    messenger.setMockMethodCallHandler(photos, (call) async {
      photoCalls.add(call);
      if (call.method == 'getPermissionState') return 2; // denied
      throw StateError('Permission must never be requested');
    });
    expect(await source.pages(includeVideos: false).toList(), isEmpty);
    expect(await source.openFile(asset, cancelToken: CancelToken()), isNull);
    expect(photoCalls.map((e) => e.method), everyElement('getPermissionState'));
    expect(exportCalls, isEmpty);
  });

  test('limited media leases original and releases exactly once', () async {
    messenger.setMockMethodCallHandler(photos, (call) async {
      photoCalls.add(call);
      if (call.method == 'getPermissionState') return 4; // limited
      throw StateError('Unexpected permission request');
    });
    final file = await source.openFile(asset, cancelToken: CancelToken());
    expect(file, isNotNull);
    await file!.dispose();
    await file.dispose();
    expect(exportCalls.map((e) => e.method), ['open', 'release']);
    expect(photoCalls.map((e) => e.method), ['getPermissionState']);
    expect((exportCalls.first.arguments as Map)['assetID'], 'original-id');
  });

  test('iCloud-only original is skipped without plugin originFile fallback',
      () async {
    messenger.setMockMethodCallHandler(originals, (call) async {
      exportCalls.add(call);
      throw PlatformException(code: 'not_local');
    });
    expect(await source.openFile(asset, cancelToken: CancelToken()), isNull);
    expect(photoCalls.map((e) => e.method), ['getPermissionState']);
    expect(exportCalls.map((e) => e.method), ['open']);
  });

  testWidgets(
      'export cancellation cancels same native request and never leases late file',
      (tester) async {
    final entered = Completer<void>();
    final pending = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(originals, (call) async {
      exportCalls.add(call);
      if (call.method == 'open') {
        entered.complete();
        return pending.future;
      }
      return null;
    });
    final token = CancelToken();
    final flight = source.openFile(asset, cancelToken: token);
    final cancelled = expectLater(flight, throwsA(isA<DioException>()));
    await tester.pump();
    expect(entered.isCompleted, isTrue);
    token.cancel('Background');
    await tester.pump();
    expect(exportCalls.map((e) => e.method), ['open', 'cancel']);
    pending.complete({'path': '/synthetic/late.data'});
    await tester.pump();
    await cancelled;
    expect(
        exportCalls.first.arguments,
        containsPair(
            'requestID', (exportCalls.last.arguments as Map)['requestID']));
  });

  test('borrowed original cleanup never deletes its library file', () async {
    final directory =
        await Directory.systemTemp.createTemp('device-sync-borrowed-');
    final original = File('${directory.path}/original.bin');
    try {
      await original.writeAsBytes([1, 2, 3]);
      final borrowed = DeviceSyncFile(file: original);
      await borrowed.dispose();
      expect(await original.readAsBytes(), [1, 2, 3]);
    } finally {
      if (await original.exists()) await original.delete();
      await directory.delete();
    }
  });

  testWidgets('GPS timeout cancels native stream and ignores late point',
      (tester) async {
    locations.resetInWidgetZone();
    DeviceSyncLocation? result;
    var completed = false;
    final flight =
        source.locate('loc-timeout', cancelToken: CancelToken()).then((value) {
      completed = true;
      result = value;
    });
    await tester.pump();
    expect(locations.listens, 1);
    locations.points
        .add(_position(DateTime.now().subtract(const Duration(minutes: 1))));
    await tester.pump();
    expect(completed, isFalse); // Cached position is never a timeout fallback.
    await tester.pump(const Duration(seconds: 10));
    await _drainLocationCallbacks(tester, () => completed);
    await flight;
    expect(completed, isTrue);
    expect(result, isNull);
    expect(locations.cancels, 1);
    locations.points.add(_position(DateTime.now()));
    await tester.pump();
    expect(result, isNull);
    expect(locations.cachedReads, 0);
    expect(locations.permissionRequests, 0);
    expect(
        locations.settings,
        isA<AppleSettings>().having(
            (e) => e.allowBackgroundLocationUpdates, 'background GPS', false));
    await _closeWidgetLocations(tester, locations);
  });

  testWidgets('GPS new fix is delivered once and stream released',
      (tester) async {
    locations.resetInWidgetZone();
    var completed = false;
    final flight =
        source.locate('loc-fresh', cancelToken: CancelToken()).then((value) {
      completed = true;
      return value;
    });
    await tester.pump();
    final now = DateTime.now();
    locations.points.add(_position(now));
    await tester.pump();
    await _drainLocationCallbacks(tester, () => completed);
    final point = await flight;
    expect(point?.clientID, 'loc-fresh');
    expect(point?.recordedAt, now.millisecondsSinceEpoch);
    expect(locations.cancels, 1);
    expect(locations.cachedReads, 0);
    await _closeWidgetLocations(tester, locations);
  });

  testWidgets('GPS cancellation and dispose release stream without late point',
      (tester) async {
    locations.resetInWidgetZone();
    var completed = false;
    final token = CancelToken();
    final flight = source.locate('loc-cancel', cancelToken: token);
    final cancelled =
        expectLater(flight, throwsA(isA<DioException>())).then((_) {
      completed = true;
    });
    await tester.pump();
    expect(await source.locate('loc-duplicate', cancelToken: CancelToken()),
        isNull);
    source.dispose();
    await tester.pump();
    await _drainLocationCallbacks(tester, () => completed);
    await cancelled;
    expect(locations.listens, 1);
    expect(locations.cancels, 1);
    locations.points.add(_position(DateTime.now()));
    await tester.pump();
    expect(await source.locate('loc-disposed', cancelToken: CancelToken()),
        isNull);
    await _closeWidgetLocations(tester, locations);
  });

  test('GPS denial only checks current permission', () async {
    locations.permission = LocationPermission.denied;
    expect(
        await source.locate('loc-denied', cancelToken: CancelToken()), isNull);
    expect(locations.permissionRequests, 0);
    expect(locations.listens, 0);
    expect(locations.cachedReads, 0);
  });
}

Future<void> _drainLocationCallbacks(
    WidgetTester tester, bool Function() ready) async {
  // Give any platform Future a real event turn, then flush the widget-zone
  // continuations. Never await a pending fake Future inside runAsync.
  for (var attempt = 0; attempt < 40 && !ready(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
    await tester.pump();
  }
  expect(ready(), isTrue,
      reason: 'Location callback or cancellation did not settle');
}

Future<void> _closeWidgetLocations(
    WidgetTester tester, _Locations locations) async {
  // Close while the controller's fake zone is still alive. Returning its close
  // Future to the outer setUp/tearDown zone can leave it waiting forever.
  final closed = locations.points.close();
  await tester.pump();
  await closed;
}

Position _position(DateTime timestamp) => Position(
    latitude: 25,
    longitude: 121,
    timestamp: timestamp,
    accuracy: 20,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

class _Locations extends GeolocatorPlatform {
  _Locations() {
    points = StreamController<Position>.broadcast(
        onListen: () => listens++, onCancel: () => cancels++);
  }

  late StreamController<Position> points;
  void resetInWidgetZone() {
    unawaited(points.close());
    points = StreamController<Position>.broadcast(
        onListen: () => listens++, onCancel: () => cancels++);
  }

  var permission = LocationPermission.whileInUse;
  var permissionRequests = 0;
  var cachedReads = 0;
  var listens = 0;
  var cancels = 0;
  LocationSettings? settings;

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    throw StateError('Automatic sync cannot request permission');
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<Position?> getLastKnownPosition(
      {bool forceLocationManager = false}) async {
    cachedReads++;
    throw StateError('Cached GPS must not be read');
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings = locationSettings;
    return points.stream;
  }
}
