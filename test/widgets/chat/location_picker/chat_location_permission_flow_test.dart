import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_source.dart';

import 'support/location_picker_test_support.dart';

class _LocationPermissionPlatform extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;
  LocationPermission decision = LocationPermission.whileInUse;
  Completer<LocationPermission>? pendingPermission;
  bool servicesEnabled = true, settingsOpen = true;
  int permissionRequests = 0,
      positions = 0,
      appSettings = 0,
      locationSettings = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission =
        await (pendingPermission?.future ?? Future.value(decision));
  }

  @override
  Future<bool> isLocationServiceEnabled() async => servicesEnabled;

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return settingsOpen;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return settingsOpen;
  }

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    positions++;
    return Position(
      latitude: 22.543096,
      longitude: 114.057865,
      timestamp: DateTime(2026),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  late _LocationPermissionPlatform platform;
  late LocationPickerHarness harness;

  setUp(() {
    final previous = GeolocatorPlatform.instance;
    platform = _LocationPermissionPlatform();
    GeolocatorPlatform.instance = platform;
    addTearDown(() => GeolocatorPlatform.instance = previous);
    final source = LocationTestSource()
      ..respond = (request) => const GeolocatorChatLocationSource()
          .locate(requestPermission: request);
    harness = LocationPickerHarness(source: source);
  });

  testWidgets(
      'entry requests permission once and accepts the native prompt result',
      (tester) async {
    final permission = Completer<LocationPermission>();
    platform.pendingPermission = permission;
    try {
      await harness.mount(tester);
      expect(platform.permissionRequests, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      permission.complete(LocationPermission.whileInUse);
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(platform.positions, 1);
      expect(locationKey('error'), findsNothing);
      expect(tester.widget<Text>(locationKey('coordinates')).data,
          contains('22.54310'));
      pauseLocationTestApp(tester);
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 1);
      expect(platform.positions, 1);
    } finally {
      if (!permission.isCompleted) {
        permission.complete(LocationPermission.denied);
      }
      await harness.close(tester);
    }
  });

  testWidgets(
      'denial keeps manual selection usable without repeated resume prompts',
      (tester) async {
    platform.decision = LocationPermission.denied;
    try {
      await harness.mount(tester);
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 1);
      expect(platform.positions, 0);
      expect(find.textContaining('定位权限未开启'), findsOneWidget);
      pauseLocationTestApp(tester);
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 1);
      await harness.selectMapPoint(tester);
      expect(locationKey('error'), findsNothing);
      expect(tester.widget<FilledButton>(locationKey('send')).onPressed,
          isNotNull);
    } finally {
      await harness.close(tester);
    }
  });

  for (final servicesOff in [false, true]) {
    testWidgets(
        'settings return silently retries ${servicesOff ? 'GPS service' : 'permission'}',
        (tester) async {
      platform.permission = servicesOff
          ? LocationPermission.whileInUse
          : LocationPermission.deniedForever;
      platform.servicesEnabled = !servicesOff;
      try {
        await harness.mount(tester);
        await tester.pumpAndSettle();
        expect(locationKey('error'), findsOneWidget);
        expect(platform.permissionRequests, 0);
        await tester.tap(locationKey('recovery'));
        await tester.pump();
        expect(
            servicesOff ? platform.locationSettings : platform.appSettings, 1);
        pauseLocationTestApp(tester);
        platform.permission = LocationPermission.whileInUse;
        platform.servicesEnabled = true;
        resumeLocationTestApp(tester);
        await tester.pumpAndSettle();
        expect(platform.positions, 1);
        expect(platform.permissionRequests, 0);
        expect(harness.source.requests, [true, servicesOff]);
        expect(locationKey('error'), findsNothing);
        pauseLocationTestApp(tester);
        resumeLocationTestApp(tester);
        await tester.pumpAndSettle();
        expect(platform.positions, 1);
      } finally {
        await harness.close(tester);
      }
    });
  }

  testWidgets('enabling GPS continues the pending first permission request',
      (tester) async {
    platform.servicesEnabled = false;
    try {
      await harness.mount(tester);
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 0);
      await tester.tap(locationKey('recovery'));
      await tester.pump();
      expect(platform.locationSettings, 1);
      pauseLocationTestApp(tester);
      platform.servicesEnabled = true;
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 1);
      expect(platform.positions, 1);
      expect(locationKey('error'), findsNothing);
      pauseLocationTestApp(tester);
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 1);
      expect(platform.positions, 1);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets('returning without granting permission does not ask again',
      (tester) async {
    platform.permission = LocationPermission.deniedForever;
    try {
      await harness.mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(locationKey('recovery'));
      await tester.pump();
      pauseLocationTestApp(tester);
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(harness.source.requests, [true, false]);
      expect(platform.permissionRequests, 0);
      expect(platform.positions, 0);
      expect(find.text('请在系统设置开启定位权限'), findsOneWidget);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
      'failed settings opening cannot trigger a later automatic location read',
      (tester) async {
    platform.permission = LocationPermission.deniedForever;
    platform.settingsOpen = false;
    try {
      await harness.mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(locationKey('recovery'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      pauseLocationTestApp(tester);
      platform.permission = LocationPermission.whileInUse;
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(harness.source.requests, [true]);
      expect(platform.positions, 0);
    } finally {
      await harness.close(tester);
    }
  });
}
