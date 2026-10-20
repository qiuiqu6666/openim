import 'location_detail_gps_fixture.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_thumbnail.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_message_data.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_message_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../location_picker/support/native_map_platform_fixture.dart';
import '../markdown/support/markdown_fixture.dart';
import 'chat_location_message_card_test.dart' show location;

void main() {
  setUp(() {
    setupMarkdownFixture();
    installUnavailableDetailGps();
  });
  tearDown(Get.reset);
  testWidgets('incoming card does not initialize AMap until detail consent',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final native = NativeMapPlatformFixture(TargetPlatform.android)..install();
    try {
      await mountMarkdown(tester, ChatLocationMessageCard(message: location()));
      expect(native.creates, isEmpty);
      await tester.tap(find.textContaining('GRAFF'));
      await tester.pumpAndSettle();
      expect(native.creates, isEmpty);
      expect(find.byKey(const ValueKey('chat-location-amap-consent')),
          findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const ValueKey('chat-location-amap-agree')));
      await tester.tap(find.byKey(const ValueKey('chat-location-amap-agree')));
      await tester.pumpAndSettle();
      expect(native.creates, hasLength(1));
      expect(native.creates.single.params['readOnly'], isTrue);
      expect(native.creates.single.params['latitude'], 39.9115);
      await native.event('onSelected', {'latitude': 20.0, 'longitude': 30.0});
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('chat-location-detail-recenter')));
      await tester.pumpAndSettle();
      expect(
          (native.calls.lastWhere((call) => call.method == 'move').arguments
              as Map)['latitude'],
          39.9115);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      native.uninstall();
      debugDefaultTargetPlatformOverride = previous;
    }
  });
  testWidgets(
      'thumbnail releases the platform map and reuses its cached bitmap',
      (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(
        {'chat_location_amap_privacy_v1': true});
    final native = NativeMapPlatformFixture(TargetPlatform.android)..install();
    try {
      native.snapshotBytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.green);
        final picture = recorder.endRecording();
        final image = await picture.toImage(8, 8);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return bytes!.buffer.asUint8List();
      });
      const data =
          ChatLocationMessageData(name: '缓存测试', point: LatLng(30.1, 120.2));
      Future<void> mount() async {
        await tester.pumpWidget(const MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 280, child: ChatLocationThumbnail(data: data)))));
        await tester.pumpAndSettle();
      }

      await mount();
      expect(native.creates, hasLength(1));
      expect(find.byType(AndroidView), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(native.calls.any((call) => call.method == 'dispose'), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(native.creates, hasLength(1));
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      native.uninstall();
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}
