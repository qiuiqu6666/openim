import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_source.dart';

import 'support/location_picker_test_support.dart';
import 'support/location_street_map_fixture.dart';

String _coordinates(WidgetTester tester) =>
    tester.widget<Text>(locationKey('coordinates')).data!;
String _name(WidgetTester tester) =>
    tester.widget<TextField>(locationKey('name')).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'map events from tap and drag send the selected coordinates and trimmed name',
      (tester) async {
    final harness = LocationPickerHarness();
    try {
      await harness.mount(tester);
      expect(harness.source.requests, [false]);
      expect(
          tester.widget<FilledButton>(locationKey('send')).onPressed, isNull);
      expect(find.byType(LocationStreetMapFixture), findsOneWidget);
      await harness.selectMapPoint(tester);
      final afterTap = _coordinates(tester);
      final map = tester.getRect(locationKey('map'));
      await tester.dragFrom(map.center, const Offset(48, -35));
      await tester.pumpAndSettle();
      expect(_coordinates(tester), isNot(afterTap));
      final selected = harness.center(tester);
      expect(selected.latitude.isFinite, isTrue);
      expect(selected.longitude.isFinite, isTrue);
      expect(selected.latitude, isNot(0));
      await tester.enterText(locationKey('name'), '  河畔公园南门  ');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(locationKey('send'));
      await tester.pumpAndSettle();
      expect(harness.returned, isTrue);
      expect(harness.result!.latitude, closeTo(selected.latitude, .000001));
      expect(harness.result!.longitude, closeTo(selected.longitude, .000001));
      expect(harness.result!.description, '河畔公园南门');
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets(
      'back cancels with null and a disposed automatic GPS cannot revive the page',
      (tester) async {
    final source = LocationTestSource();
    final pending = Completer<LatLng?>();
    source.respond = (_) => pending.future;
    final harness = LocationPickerHarness(source: source);
    try {
      await harness.mount(tester);
      expect(source.requests, [false]);
      expect(
          tester.widget<FilledButton>(locationKey('send')).onPressed, isNull);
      await tester.tap(locationKey('back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.returned, isTrue);
      expect(harness.result, isNull);
      pending.complete(const LatLng(22.543096, 114.057865));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(locationKey('map'), findsNothing);
      expect(source.requests, [false]);
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete(null);
      await harness.close(tester);
    }
  });

  testWidgets(
      'loading is stable and nonduplicating, late GPS loses to a map tap, and timeout retries',
      (tester) async {
    final harness = LocationPickerHarness();
    final pending = Completer<LatLng?>();
    try {
      await harness.mount(tester);
      await harness.selectMapPoint(tester);
      await tester.enterText(locationKey('name'), '保留的位置名称');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final beforeMap = tester.getRect(locationKey('map'));
      final beforeSelection = tester.getRect(locationKey('selection'));
      final beforeCoordinates = _coordinates(tester);
      harness.source.respond = (_) => pending.future;
      await tester.tap(locationKey('locate'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(locationKey('locate'));
      await tester.pump();
      expect(harness.source.requests, [false, true]);
      expect(tester.getRect(locationKey('map')), beforeMap);
      expect(tester.getRect(locationKey('selection')), beforeSelection);
      expect(_coordinates(tester), beforeCoordinates);
      expect(_name(tester), '保留的位置名称');
      await harness.selectMapPoint(tester);
      final manualCoordinates = _coordinates(tester);
      pending.complete(const LatLng(50, 60));
      await tester.pumpAndSettle();
      expect(_coordinates(tester), manualCoordinates);
      expect(_name(tester), '保留的位置名称');
      harness.source.respond = (_) => Future.error(
          const ChatLocationException(ChatLocationFailure.timeout));
      await tester.tap(locationKey('locate'));
      await tester.pumpAndSettle();
      expect(locationKey('error'), findsOneWidget);
      expect(find.textContaining('定位超时'), findsOneWidget);
      expect(_coordinates(tester), manualCoordinates);
      expect(_name(tester), '保留的位置名称');
      harness.source.respond = (_) async => const LatLng(22.543096, 114.057865);
      await tester.tap(locationKey('locate'));
      await tester.pumpAndSettle();
      expect(locationKey('error'), findsNothing);
      expect(_coordinates(tester), contains('22.54310'));
      expect(_coordinates(tester), contains('114.05787'));
      expect(_name(tester), '保留的位置名称');
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete(null);
      await harness.close(tester);
    }
  });

  testWidgets(
      'opaque route and background reject GPS without losing the current point',
      (tester) async {
    final harness = LocationPickerHarness();
    final coveredRead = Completer<LatLng?>();
    final backgroundRead = Completer<LatLng?>();
    try {
      await harness.mount(tester);
      await harness.selectMapPoint(tester);
      final coordinates = _coordinates(tester);
      harness.source.respond = (_) => coveredRead.future;
      await tester.tap(locationKey('locate'));
      await tester.pump();
      unawaited(harness.navigator.currentState!.push<void>(MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Text('opaque coverage fixture')))));
      await tester.pump(const Duration(milliseconds: 400));
      coveredRead.complete(const LatLng(50, 60));
      await tester.pump();
      harness.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_coordinates(tester), coordinates);
      harness.source.respond = (_) => backgroundRead.future;
      await tester.tap(locationKey('locate'));
      await tester.pump();
      pauseLocationTestApp(tester);
      backgroundRead.complete(const LatLng(40, 90));
      await tester.pump();
      resumeLocationTestApp(tester);
      await tester.pumpAndSettle();
      expect(_coordinates(tester), coordinates);
      expect(harness.source.requests, [false, true, true]);
      harness.source.respond = (_) async => const LatLng(22, 114);
      await tester.tap(locationKey('locate'));
      await tester.pumpAndSettle();
      expect(_coordinates(tester), contains('22.00000'));
      expect(tester.takeException(), isNull);
    } finally {
      if (!coveredRead.isCompleted) coveredRead.complete(null);
      if (!backgroundRead.isCompleted) backgroundRead.complete(null);
      await harness.close(tester);
    }
  });
}
