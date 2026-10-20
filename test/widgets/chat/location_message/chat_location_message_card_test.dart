import 'location_detail_gps_fixture.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_message_card.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_message_data.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../markdown/support/markdown_fixture.dart';
import '../location_picker/support/location_street_map_fixture.dart';

Message location(
        {bool outgoing = true,
        String description = 'GRAFF格拉夫(北京王府中環珠宝店)\n北京市东城区 · 王府井大街',
        double latitude = 39.9115}) =>
    markdownMessage('',
        id: 'location-card',
        outgoing: outgoing,
        type: MessageType.location,
        extra: {
          'locationElem': {
            'latitude': latitude,
            'longitude': 116.4042,
            'description': description
          }
        });

void main() {
  setUp(() {
    setupMarkdownFixture();
    installUnavailableDetailGps();
  });
  tearDown(Get.reset);
  test('legacy names and real addresses parse without inventing address data',
      () {
    expect(ChatLocationMessageData.parse('旧地点', 31, 121).address, isEmpty);
    expect(ChatLocationMessageData.parse('地点/////地址', 31, 121).address, '地址');
    expect(ChatLocationMessageData.parse('地点\n地址', 31, 121).name, '地点');
    expect(ChatLocationMessageData.parse('地点', 91, 121).point, isNull);
    expect(ChatLocationMessageData.parse('地点', double.nan, 121).point, isNull);
  });
  for (final dark in [false, true]) {
    for (final outgoing in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('card layout dark=$dark outgoing=$outgoing scale=$scale',
            (tester) async {
          final message = location(outgoing: outgoing);
          final original = message.toJson();
          await mountMarkdown(
              tester, ChatItemView(message: message, onTapUserProfile: (_) {}),
              brightness: dark ? Brightness.dark : Brightness.light,
              width: 320,
              textScale: scale);
          await tester.pumpAndSettle();
          final card = find.byKey(const ValueKey('chat-location-message-card'));
          expect(tester.widget<Material>(card).color,
              AppTokens.surface(dark: dark));
          expect(find.textContaining('39.9115'), findsNothing);
          expect(find.textContaining('GRAFF'), findsNothing);
          expect(find.textContaining('北京市东城区'), findsNothing);
          expect(find.text('14:08'), findsOneWidget);
          expect(find.byType(ChatReadReceiptIcon),
              outgoing ? findsOneWidget : findsNothing);
          final rect = tester.getRect(card);
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(tester.getRect(find.text('14:08')).bottom,
              lessThanOrEqualTo(rect.bottom));
          expect(message.toJson(), original);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets(
      'tap opens an in-app read-only map and back preserves the message',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'chat_location_amap_privacy_v1': true});
    final message = location();
    final original = message.toJson();
    var readOnly = false;
    await mountMarkdown(
        tester,
        ChatLocationMessageCard(
            message: message,
            mapBuilder: (context, options) {
              readOnly = options.readOnly;
              return LocationStreetMapFixture(
                  center: options.selected!,
                  enabled: false,
                  onReady: options.onReady,
                  onSelected: options.onSelected);
            }));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-location-message-card')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatLocationDetailPage), findsOneWidget);
    expect(readOnly, isTrue);
    await tester
        .tap(find.byKey(const ValueKey('chat-location-detail-recenter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-location-detail-back')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatLocationDetailPage), findsNothing);
    expect(find.byType(ChatLocationMessageCard), findsOneWidget);
    expect(message.toJson(), original);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'legacy message has no fabricated address and invalid coordinates do not navigate',
      (tester) async {
    await mountMarkdown(
        tester,
        ChatLocationMessageCard(
            message: location(description: '旧地点', latitude: 91)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-location-message-card')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatLocationDetailPage), findsNothing);
    expect(find.textContaining('王府井'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('render card and in-app detail previews', (tester) async {
    if (markdownPreviewDirectory.isEmpty) return;
    await tester.runAsync(loadMarkdownPreviewFonts);
    SharedPreferences.setMockInitialValues(
        {'chat_location_amap_privacy_v1': true});
    for (final dark in [false, true]) {
      await mountMarkdown(
          tester,
          Align(
              alignment: Alignment.topRight,
              child: ChatLocationMessageCard(
                  message: location(),
                  time: '18:35',
                  status: const Icon(Icons.check, size: 16),
                  mapBuilder: (_, options) => LocationStreetMapFixture(
                      center: options.selected!,
                      enabled: false,
                      onReady: options.onReady,
                      onSelected: (_) {}))),
          width: 390,
          brightness: dark ? Brightness.dark : Brightness.light);
      await tester.pumpAndSettle();
      await tester.runAsync(() => saveMarkdownPreview(
          tester, 'location-card-${dark ? 'dark' : 'light'}'));
      await tester
          .tap(find.byKey(const ValueKey('chat-location-message-card')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find
            .ancestor(
                of: find.byType(ChatLocationDetailPage),
                matching: find.byType(RepaintBoundary))
            .first);
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
                '$markdownPreviewDirectory/location-detail-${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byKey(const ValueKey('chat-location-detail-back')));
      await tester.pumpAndSettle();
    }
  });
}
