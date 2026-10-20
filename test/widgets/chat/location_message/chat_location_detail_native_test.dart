import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_picker/native/chat_location_native_map.dart';
import 'package:openim_common/src/widgets/chat/location_picker/native/chat_location_native_map_options.dart';
import '../location_picker/support/native_map_platform_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform detail camera and satellite keep the shared pin',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      final native = NativeMapPlatformFixture(platform)..install();
      Future<void> mount(
          {bool satellite = false, LatLng? camera, int request = 0}) async {
        await tester.pumpWidget(MaterialApp(
            home: SizedBox(
                width: 390,
                height: 844,
                child: ChatLocationNativeMap(
                    requireConsent: false,
                    options: ChatLocationNativeMapOptions(
                        selected: const LatLng(11.55, 104.94),
                        readOnly: true,
                        detail: true,
                        dark: false,
                        active: true,
                        satellite: satellite,
                        cameraTarget: camera,
                        userLocation: camera,
                        viewportInsets:
                            const EdgeInsets.only(top: 80, bottom: 200),
                        centerRequest: request,
                        onSelected: (_) => fail('Read-only pin changed'),
                        onReady: () {},
                        onError: (_) => fail('Unexpected map error'))))));
        await tester.pumpAndSettle();
      }

      try {
        await mount();
        expect(native.creates.single.params['detail'], isTrue);
        await mount(camera: const LatLng(12, 105), request: 1);
        final movedPin =
            native.calls.lastWhere((c) => c.method == 'move').arguments as Map;
        final view = native.calls
            .lastWhere((c) => c.method == 'detailView')
            .arguments as Map;
        expect(movedPin['latitude'], 11.55);
        expect(view['latitude'], 12);
        expect(view['userLatitude'], 12);
        expect(view['bottomInset'], 200);
        await mount(satellite: true, camera: const LatLng(12, 105), request: 1);
        final layer = native.calls
            .lastWhere((c) => c.method == 'detailView')
            .arguments as Map;
        expect(layer['satellite'], isTrue);
        expect(layer['moveCamera'], isFalse);
        await native.event('onSelected', {'latitude': 20, 'longitude': 30});
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        native.uninstall();
        debugDefaultTargetPlatformOverride = previous;
      }
    });
  }
}
