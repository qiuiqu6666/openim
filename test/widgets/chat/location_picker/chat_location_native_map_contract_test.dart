import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_picker/native/chat_location_native_map.dart';
import 'package:openim_common/src/widgets/chat/location_picker/native/chat_location_native_map_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/native_map_platform_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Android and iOS native map channels preserve selection, camera intent and lifecycle',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    try {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        SharedPreferences.setMockInitialValues(
            {'chat_location_amap_privacy_v1': true});
        final native = NativeMapPlatformFixture(platform)..install();
        final selected = <LatLng>[];
        final errors = <ChatLocationMapFailure>[];
        var ready = 0;
        Future<void> mount(
            {LatLng? point,
            int centerRequest = 0,
            bool dark = false,
            bool active = true}) async {
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: SizedBox(
            width: 300,
            height: 300,
            child: ChatLocationNativeMap(
                options: ChatLocationNativeMapOptions(
              selected: point,
              dark: dark,
              active: active,
              centerRequest: centerRequest,
              onSelected: selected.add,
              onReady: () => ready++,
              onError: errors.add,
            )),
          ))));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }

        try {
          await mount();
          expect(native.creates, hasLength(1));
          expect(native.creates.single.viewType, 'openim/chat-location-map');
          expect(native.creates.single.params['privacyAgreed'],
              platform == TargetPlatform.android);
          expect(native.creates.single.params['dark'], isFalse);
          await native.event('onReady');
          await tester.pump();
          expect(ready, 1);
          expect(errors, isEmpty);
          await native.event(
              'onSelected', {'latitude': 31.2304, 'longitude': 121.4737});
          await tester.pump();
          expect(selected, [const LatLng(31.2304, 121.4737)]);

          final movesBeforeManualEcho =
              native.calls.where((call) => call.method == 'move').length;
          await mount(point: selected.single);
          expect(native.calls.where((call) => call.method == 'move').length,
              movesBeforeManualEcho,
              reason:
                  'A native manual selection must not echo into another camera move.');
          await mount(
              point: const LatLng(22.543096, 114.057865),
              centerRequest: 1,
              dark: true);
          final move = native.calls.lastWhere((call) => call.method == 'move');
          expect(move.arguments,
              {'latitude': 22.543096, 'longitude': 114.057865, 'zoom': 16});
          expect(
              native.calls
                  .lastWhere((call) => call.method == 'style')
                  .arguments,
              {'dark': true});

          await mount(
              point: const LatLng(22.543096, 114.057865),
              centerRequest: 1,
              dark: true,
              active: false);
          expect(
              native.calls
                  .lastWhere((call) => call.method == 'setActive')
                  .arguments,
              {'active': false});
          await native
              .event('onSelected', {'latitude': 40.0, 'longitude': 90.0});
          await tester.pump();
          expect(selected, hasLength(1),
              reason: 'Covered native maps cannot change the selected point.');
          await mount(
              point: const LatLng(22.543096, 114.057865),
              centerRequest: 1,
              dark: true);
          await native.event('onError', {'code': 'unavailable'});
          await tester.pump();
          expect(errors, contains(ChatLocationMapFailure.unavailable));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(native.calls.any((call) => call.method == 'dispose'), isTrue);
          expect(native.platformCalls.any((call) => call.method == 'dispose'),
              isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          native.uninstall();
        }
      }
    } finally {
      // Restore inside the body before Flutter's foundation invariant runs.
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets(
      'Android waits for explicit consent and a missing map key never signals ready or selection',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final native = NativeMapPlatformFixture(TargetPlatform.android)
      ..statusError = 'keyMissing'
      ..install();
    var ready = 0;
    final selected = <LatLng>[];
    final errors = <ChatLocationMapFailure>[];
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
        width: 300,
        height: 450,
        child: ChatLocationNativeMap(
            options: ChatLocationNativeMapOptions(
          selected: null,
          dark: false,
          active: true,
          centerRequest: 0,
          onSelected: selected.add,
          onReady: () => ready++,
          onError: errors.add,
        )),
      ))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-location-amap-consent')),
          findsOneWidget);
      expect(find.byType(AndroidView), findsNothing);
      expect(native.creates, isEmpty);
      expect(ready, 0);
      final agree = find.byKey(const ValueKey('chat-location-amap-agree'));
      await tester.ensureVisible(agree);
      await tester.tap(agree);
      await tester.pumpAndSettle();
      expect(native.creates, hasLength(1));
      expect(native.creates.single.params['privacyAgreed'], isTrue);
      expect(
          (await SharedPreferences.getInstance())
              .getBool('chat_location_amap_privacy_v1'),
          isTrue);
      expect(errors, [ChatLocationMapFailure.keyMissing]);
      expect(ready, 0);
      await native.event('onReady');
      await native.event('onSelected', {'latitude': 31.0, 'longitude': 121.0});
      await tester.pump();
      expect(ready, 0);
      expect(selected, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      native.uninstall();
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
