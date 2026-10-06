import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/location_picker_test_support.dart';
import 'support/location_street_map_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLocationPreviewFonts);

  for (final variant in const [
    (name: 'light', size: Size(393, 852), scale: 1.0, dark: false),
    (name: 'dark', size: Size(393, 852), scale: 1.0, dark: true),
    (name: '320-large-text', size: Size(320, 640), scale: 2.0, dark: false),
    (name: 'short-large-text', size: Size(393, 393), scale: 2.0, dark: false),
    (name: 'landscape', size: Size(852, 393), scale: 1.0, dark: false),
  ]) {
    testWidgets('location controls remain reachable ${variant.name}',
        (tester) async {
      final source = LocationTestSource()
        ..respond = (_) async => const LatLng(22.543096, 114.057865);
      final harness = LocationPickerHarness(source: source);
      try {
        await harness.mount(tester,
            size: variant.size,
            textScale: variant.scale,
            brightness: variant.dark ? Brightness.dark : Brightness.light);
        await tester.pumpAndSettle();
        expect(find.byType(LocationStreetMapFixture), findsOneWidget);
        expect(source.requests, [false]);
        expect(Theme.of(tester.element(locationKey('name'))).brightness,
            variant.dark ? Brightness.dark : Brightness.light);
        final name = tester.widget<TextField>(locationKey('name'));
        expect(name.maxLength, 120);
        expect(name.decoration!.filled, isTrue);
        await tester.enterText(locationKey('name'), '测试地点 · 河畔公园');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(locationKey('map')).height, greaterThan(0));
        for (final control in ['name', 'send', 'locate', 'back']) {
          await Scrollable.ensureVisible(tester.element(locationKey(control)),
              alignment: .5);
          await tester.pumpAndSettle();
          expect(locationKey(control).hitTestable(), findsOneWidget);
          final rect = tester.getRect(locationKey(control));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(variant.size.width + 1));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(variant.size.height + 1));
        }
        expect(tester.widget<FilledButton>(locationKey('send')).onPressed,
            isNotNull);
        expect(tester.getSize(locationKey('send')).height,
            greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await harness.export(tester, variant.name);

        if (variant.name == 'light') {
          await tester.enterText(locationKey('name'), '键盘弹出后保留的位置名称');
          tester.view.viewInsets = const FakeViewPadding(bottom: 340);
          await tester.pumpAndSettle();
          await tester.ensureVisible(locationKey('name'));
          await tester.pumpAndSettle();
          expect(tester.getRect(locationKey('name')).bottom,
              lessThanOrEqualTo(variant.size.height - 340 + 1));
          expect(tester.takeException(), isNull);
          await harness.export(tester, 'keyboard-focused');
          await tester.ensureVisible(locationKey('send'));
          await tester.pumpAndSettle();
          expect(locationKey('send').hitTestable(), findsOneWidget);
          expect(tester.getRect(locationKey('send')).bottom,
              lessThanOrEqualTo(variant.size.height - 340 + 1));
          expect(tester.widget<TextField>(locationKey('name')).controller!.text,
              '键盘弹出后保留的位置名称');
          expect(tester.takeException(), isNull);
          await harness.export(tester, 'keyboard-action');
        }
      } finally {
        tester.view.resetViewInsets();
        await harness.close(tester);
      }
    });
  }
}
