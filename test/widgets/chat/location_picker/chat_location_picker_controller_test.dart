import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_picker/chat_location_picker_controller.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_source.dart';

import 'support/chat_location_test_source.dart';

class _PermissionPlatform extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;
  int permissionRequests = 0, positions = 0;
  LocationSettings? settings;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return LocationPermission.whileInUse;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    positions++;
    settings = locationSettings;
    throw TimeoutException('GPS test timeout');
  }
}

void main() {
  test(
      'automatic reads never request permission; the 20s native failure and manual retry stay explicit',
      () async {
    final previous = GeolocatorPlatform.instance;
    final platform = _PermissionPlatform();
    GeolocatorPlatform.instance = platform;
    try {
      const source = GeolocatorChatLocationSource();
      for (final permission in [
        LocationPermission.denied,
        LocationPermission.deniedForever
      ]) {
        platform.permission = permission;
        expect(await source.locate(requestPermission: false), isNull);
      }
      expect(platform.permissionRequests, 0);
      expect(platform.positions, 0);
      platform.permission = LocationPermission.denied;
      await expectLater(
          source.locate(requestPermission: true),
          throwsA(isA<ChatLocationException>().having((error) => error.failure,
              'failure', ChatLocationFailure.timeout)));
      expect(platform.permissionRequests, 1);
      expect(platform.positions, 1);
      expect(platform.settings!.timeLimit, const Duration(seconds: 20));
    } finally {
      GeolocatorPlatform.instance = previous;
    }
    final source = LocationTestSource();
    final controller = ChatLocationPickerController(source: source);
    addTearDown(controller.dispose);
    await controller.locate(requestPermission: false);
    expect(controller.selected, isNull);
    expect(controller.failure, isNull);
    source.respond = (_) =>
        Future.error(const ChatLocationException(ChatLocationFailure.denied));
    await controller.locate(requestPermission: false);
    expect(controller.failure, isNull);
    controller.select(const LatLng(31.23, 121.47));
    source.respond = (_) =>
        Future.error(const ChatLocationException(ChatLocationFailure.timeout));
    await controller.locate();
    expect(controller.failure, ChatLocationFailure.timeout);
    expect(controller.selected, const LatLng(31.23, 121.47));
    source.respond = (_) async => const LatLng(22.543096, 114.057865);
    await controller.locate();
    expect(controller.selected, const LatLng(22.543096, 114.057865));
    expect(controller.failure, isNull);
    expect(controller.locating, isFalse);
    expect(source.requests, [false, false, true, true]);
  });

  test('a manual map selection fences both late GPS success and failure',
      () async {
    final source = LocationTestSource();
    final controller = ChatLocationPickerController(source: source);
    addTearDown(controller.dispose);
    final pending = Completer<LatLng?>();
    source.respond = (_) => pending.future;
    final locating = controller.locate();
    controller.select(const LatLng(23.1, 181));
    final manual = controller.selected;
    expect(manual, const LatLng(23.1, -179));
    pending.complete(const LatLng(50, 60));
    await locating;
    expect(controller.selected, manual);
    final failure = Completer<LatLng?>();
    source.respond = (_) => failure.future;
    final retry = controller.locate();
    controller.select(manual!);
    failure.completeError(
        const ChatLocationException(ChatLocationFailure.disabled));
    await retry;
    expect(controller.selected, manual);
    expect(controller.failure, isNull);
    expect(controller.locating, isFalse);
  });

  test(
      'background or opaque coverage rejects late data without overlapping GPS',
      () async {
    final source = LocationTestSource();
    final controller = ChatLocationPickerController(source: source);
    addTearDown(controller.dispose);
    controller.select(const LatLng(31, 121));
    final pending = Completer<LatLng?>();
    source.respond = (_) => pending.future;
    final locating = controller.locate();
    controller.setActive(false);
    await controller.locate();
    controller.select(const LatLng(0, 0));
    controller.setActive(true);
    await controller.locate();
    expect(source.requests, [true]);
    expect(controller.locating, isTrue);
    pending.complete(const LatLng(45, 90));
    await locating;
    expect(controller.selected, const LatLng(31, 121));
    expect(controller.locating, isFalse);
    source.respond = (_) async => const LatLng(32, 122);
    await controller.locate();
    expect(controller.selected, const LatLng(32, 122));
    expect(source.requests, [true, true]);
  });

  test(
      'only accepted GPS fixes advance recenter intent, including the same point',
      () async {
    final source = LocationTestSource();
    final controller = ChatLocationPickerController(source: source);
    addTearDown(controller.dispose);
    const point = LatLng(22.543096, 114.057865);
    controller.select(point);
    expect(controller.locationRevision, 0);
    source.respond = (_) async => point;
    await controller.locate();
    expect(controller.selected, point);
    expect(controller.locationRevision, 1);
    await controller.locate();
    expect(controller.selected, point);
    expect(controller.locationRevision, 2);
    controller.select(point);
    expect(controller.locationRevision, 2);

    final manualRead = Completer<LatLng?>();
    source.respond = (_) => manualRead.future;
    final locatingBeforeSelection = controller.locate();
    const manual = LatLng(31.2304, 121.4737);
    controller.select(manual);
    manualRead.complete(point);
    await locatingBeforeSelection;
    expect(controller.selected, manual);
    expect(controller.locationRevision, 2);

    final backgroundRead = Completer<LatLng?>();
    source.respond = (_) => backgroundRead.future;
    final locatingBeforeBackground = controller.locate();
    controller.setActive(false);
    controller.setActive(true);
    backgroundRead.complete(point);
    await locatingBeforeBackground;
    expect(controller.selected, manual);
    expect(controller.locationRevision, 2);
  });

  test(
      'finite coordinate boundaries and wrapped longitude never corrupt selection',
      () async {
    final source = LocationTestSource();
    final controller = ChatLocationPickerController(source: source);
    addTearDown(controller.dispose);
    controller.select(const LatLng(-90, -180));
    expect(controller.selected, const LatLng(-90, -180));
    controller.select(const LatLng(90, 180));
    expect(controller.selected, const LatLng(90, 180));
    controller.select(const LatLng(20, 540));
    expect(controller.selected, const LatLng(20, -180));
    controller.select(const LatLng(20, -541));
    expect(controller.selected, const LatLng(20, 179));
    for (final invalid in const [
      LatLng(90.00001, 0),
      LatLng(-90.00001, 0),
      LatLng(double.nan, 0),
      LatLng(20, double.infinity),
    ]) {
      controller.select(invalid);
      expect(controller.selected, const LatLng(20, 179));
      expect(controller.failure, ChatLocationFailure.unavailable);
    }
    source.respond = (_) async => const LatLng(20, 181);
    await controller.locate();
    expect(controller.selected, const LatLng(20, 179));
    expect(controller.failure, ChatLocationFailure.unavailable);
  });

  test(
      'disposing during GPS drops data and notifications and prevents later reads',
      () async {
    final source = LocationTestSource();
    final pending = Completer<LatLng?>();
    source.respond = (_) => pending.future;
    final controller = ChatLocationPickerController(source: source);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final locating = controller.locate();
    final beforeDispose = notifications;
    controller.dispose();
    pending.complete(const LatLng(31, 121));
    await locating;
    await controller.locate();
    expect(notifications, beforeDispose);
    expect(controller.selected, isNull);
    expect(controller.isActive, isFalse);
    expect(source.requests, [true]);
  });
}
