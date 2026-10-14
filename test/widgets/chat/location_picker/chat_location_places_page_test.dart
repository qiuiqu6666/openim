import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_place.dart';
import 'support/location_picker_test_support.dart';

void main() {
  testWidgets(
      'search selection sends the provider point and name from the top action',
      (tester) async {
    final harness = LocationPickerHarness(
        placeSearch: (query, center) async => [
              ChatLocationPlace(
                  id: 'park',
                  name: '河畔公园',
                  address: '公园路1号',
                  point: const LatLng(31.2, 121.4)),
            ]);
    try {
      await harness.mount(tester);
      expect(locationKey('name'), findsNothing);
      await tester.enterText(locationKey('search'), '公园');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(locationKey('place-park'));
      await tester.tap(locationKey('place-park'));
      await tester.pumpAndSettle();
      expect(tester.getRect(locationKey('send')).bottom,
          lessThan(tester.getRect(locationKey('map')).top + 1));
      await tester.tap(locationKey('send'));
      await tester.pumpAndSettle();
      expect(harness.result?.latitude, 31.2);
      expect(harness.result?.longitude, 121.4);
      expect(harness.result?.description, '河畔公园\n公园路1号');
    } finally {
      await harness.close(tester);
    }
  });
}
