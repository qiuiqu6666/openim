import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_detail_page.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_message_data.dart';
import 'package:openim_common/src/widgets/chat/location_message/detail/chat_location_address_source.dart';
import 'package:openim_common/src/widgets/chat/location_picker/native/chat_location_native_map_options.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_source.dart';
import '../markdown/support/markdown_fixture.dart';

class AddressSource extends ChatLocationAddressSource {
  int calls = 0;
  LatLng? point;
  Completer<ChatLocationAddress> pending = Completer();
  @override
  Future<ChatLocationAddress> resolve(LatLng value, String locale) {
    calls++;
    point = value;
    return pending.future;
  }
}

class Gps implements ChatLocationSource {
  @override
  Future<LatLng?> locate({required bool requestPermission}) async =>
      const LatLng(12, 105);
}

void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);
  late ChatLocationNativeMapOptions options;
  Future<void> mount(WidgetTester tester, AddressSource source,
      {String address = ''}) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatLocationDetailPage(
            data: ChatLocationMessageData(
                name: '位置', address: address, point: const LatLng(39.9, 116.4)),
            addressSource: source,
            locationSource: Gps(),
            mapBuilder: (_, value) {
              options = value;
              return const SizedBox.expand();
            })));
    options.onReady();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'resolves shared coordinate once, not GPS, and displays returned address',
      (tester) async {
    final source = AddressSource();
    await mount(tester, source);
    expect(source.calls, 1);
    expect(source.point, const LatLng(39.9, 116.4));
    expect(find.textContaining('Finding address'), findsOneWidget);
    options.onReady();
    await tester.pump();
    expect(source.calls, 1);
    source.pending.complete(
        const ChatLocationAddress(name: '王府井', address: '北京市东城区王府井大街'));
    await tester.pumpAndSettle();
    expect(find.text('王府井'), findsOneWidget);
    expect(find.text('北京市东城区王府井大街'), findsOneWidget);
    expect(options.selected, const LatLng(39.9, 116.4));
    expect(options.userLocation, const LatLng(12, 105));
  });
  testWidgets('existing message address is never queried or replaced',
      (tester) async {
    final source = AddressSource();
    await mount(tester, source, address: '消息自带地址');
    expect(source.calls, 0);
    expect(find.text('消息自带地址'), findsOneWidget);
  });
  testWidgets('failed lookup is visible and retry can recover', (tester) async {
    final source = AddressSource();
    await mount(tester, source);
    source.pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Address unavailable'), findsOneWidget);
    source.pending = Completer();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(source.calls, 2);
    source.pending
        .complete(const ChatLocationAddress(name: '街道', address: '真实地址'));
    await tester.pumpAndSettle();
    expect(find.text('真实地址'), findsOneWidget);
  });
  testWidgets('closing the page ignores late address results', (tester) async {
    final source = AddressSource();
    await mount(tester, source);
    await tester.pumpWidget(const SizedBox());
    source.pending
        .complete(const ChatLocationAddress(name: '街道', address: '真实地址'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('native address adapter sends WGS84 and rejects empty results',
      () async {
    const channel = MethodChannel('openim/location-address');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect((call.arguments as Map)['latitude'], 39.9);
      expect((call.arguments as Map)['locale'], 'zh-CN');
      return {'address': '  '};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
        const ChatLocationAddressSource()
            .resolve(const LatLng(39.9, 116.4), 'zh-CN'),
        throwsStateError);
  });
}

