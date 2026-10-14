import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_picker/chat_location_places_controller.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_place.dart';

const park = ChatLocationPlace(
    id: 'park', name: '公园', address: '公园路', point: LatLng(31, 121));
void main() {
  testWidgets(
      'typing is debounced and an old response cannot replace a new query',
      (tester) async {
    final old = Completer<List<ChatLocationPlace>>();
    final calls = <String>[];
    final controller = ChatLocationPlacesController()
      ..search = (query, center) {
        calls.add(query);
        return query == 'old' ? old.future : Future.value([park]);
      };
    controller.update(text: 'o');
    controller.update(text: 'old');
    await tester.pump(const Duration(milliseconds: 350));
    controller.update(text: 'new');
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, ['old', 'new']);
    expect(controller.places, [park]);
    old.complete([]);
    await tester.pump();
    expect(controller.places, [park]);
    controller.dispose();
  });

  testWidgets(
      'covered routes reject pending searches and resume at the current point',
      (tester) async {
    final pending = Completer<List<ChatLocationPlace>>();
    final controller = ChatLocationPlacesController()
      ..search = (_, __) => pending.future;
    controller.update(point: const LatLng(31, 121));
    await tester.pump(const Duration(milliseconds: 350));
    controller.setActive(false);
    pending.complete([park]);
    await tester.pump();
    expect(controller.places, isEmpty);
    LatLng? requestedCenter;
    controller.search = (_, center) async {
      requestedCenter = center;
      return [park];
    };
    controller.setActive(true);
    await tester.pump(const Duration(milliseconds: 351));
    expect(requestedCenter?.latitude, 31);
    expect(requestedCenter?.longitude, 121);
    expect(controller.places, [park]);
    controller.dispose();
  });

  testWidgets('failed searches retry and disposal ignores delayed replies',
      (tester) async {
    final controller = ChatLocationPlacesController()
      ..search = (_, __) async => throw StateError('offline');
    controller.update(text: 'park');
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.failed, isTrue);
    final pending = Completer<List<ChatLocationPlace>>();
    controller.search = (_, __) => pending.future;
    controller.update();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.failed, isFalse);
    controller.dispose();
    pending.complete([park]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
