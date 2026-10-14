import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'support/location_picker_test_support.dart';
import 'support/native_map_platform_fixture.dart';

void main() {
  setUpAll(loadLocationPreviewFonts);
  for (final dark in [false, true]) {
    testWidgets(
        'full page gates map, location and search until consent, dark=$dark',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      final native = NativeMapPlatformFixture(TargetPlatform.android)
        ..install();
      final harness = LocationPickerHarness(
          useNativeMap: true,
          source: LocationTestSource()
            ..respond = (_) async => const LatLng(31, 121));
      try {
        await harness.mount(tester,
            brightness: dark ? Brightness.dark : Brightness.light);
        await tester.pumpAndSettle();
        expect(native.creates, isEmpty);
        expect(harness.source.requests, isEmpty);
        expect(locationKey('details-scroll'), findsNothing);
        expect(locationKey('search'), findsNothing);
        expect(
            tester.widget<FilledButton>(locationKey('send')).onPressed, isNull);
        final disabledSendRect = tester.getRect(locationKey('send'));
        expect(locationKey('amap-privacy-link'), findsOneWidget);
        await harness.export(tester, dark ? 'consent-dark' : 'consent-light');
        await tester.tap(locationKey('amap-agree'));
        await tester.pumpAndSettle();
        expect(native.creates, hasLength(1));
        expect(tester.widget<FilledButton>(locationKey('send')).onPressed,
            isNotNull);
        expect(tester.getRect(locationKey('send')), disabledSendRect,
            reason: 'Consent and selected states share send-button geometry.');
        expect(harness.source.requests, [true]);
        expect(locationKey('search'), findsOneWidget);
        expect(
            (await SharedPreferences.getInstance())
                .getBool('chat_location_amap_privacy_v1'),
            isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.close(tester);
        native.uninstall();
        debugDefaultTargetPlatformOverride = previous;
      }
    });
  }
  testWidgets('declining consent cancels without loading map or requesting GPS',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final native = NativeMapPlatformFixture(TargetPlatform.android)..install();
    final harness = LocationPickerHarness(useNativeMap: true);
    try {
      await harness.mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(locationKey('amap-decline'));
      await tester.pumpAndSettle();
      expect(harness.returned, isTrue);
      expect(harness.result, isNull);
      expect(native.creates, isEmpty);
      expect(harness.source.requests, isEmpty);
      expect(
          (await SharedPreferences.getInstance())
              .getBool('chat_location_amap_privacy_v1'),
          isNot(true));
    } finally {
      await harness.close(tester);
      native.uninstall();
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}
