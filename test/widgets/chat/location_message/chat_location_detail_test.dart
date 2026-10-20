import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:openim_common/src/widgets/liquid_glass_surface.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_detail_page.dart';
import 'package:openim_common/src/widgets/chat/location_message/chat_location_message_data.dart';
import 'package:openim_common/src/widgets/chat/location_message/detail/chat_location_detail_actions.dart';
import 'package:openim_common/src/widgets/chat/location_picker/data/chat_location_source.dart';
import 'package:openim_common/src/widgets/chat/location_picker/native/chat_location_native_map_options.dart';
import '../markdown/support/markdown_fixture.dart';

class Source implements ChatLocationSource {
  Source({this.pending = false});
  final bool pending;
  int calls = 0;
  final completer = Completer<LatLng?>();
  @override
  Future<LatLng?> locate({required bool requestPermission}) {
    calls++;
    return pending ? completer.future : Future.value(const LatLng(12, 105));
  }
}

class Actions extends ChatLocationDetailActions {
  int shares = 0, routes = 0;
  ChatLocationMessageData? shared, routed;
  bool fail = false;
  @override
  Future<List<AvailableMap>> installedMaps() async => [];
  @override
  Future<void> share(ChatLocationMessageData data, Rect origin) async {
    shares++;
    shared = data;
    if (fail) throw StateError('failed');
  }

  @override
  Future<void> directions(
      ChatLocationMessageData data, AvailableMap? map) async {
    routes++;
    routed = data;
  }
}

const data = ChatLocationMessageData(
    name: '分享的地点名称', address: '详细街道地址', point: LatLng(11.55, 104.94));
void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);
  late ChatLocationNativeMapOptions latest;
  Future<void> mount(WidgetTester tester, Source source, Actions actions,
      {Size size = const Size(390, 844),
      double scale = 1,
      bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: ChatLocationDetailPage(
            data: data,
            locationSource: source,
            actions: actions,
            mapBuilder: (_, options) {
              latest = options;
              return const ColoredBox(color: Colors.grey);
            })));
    latest.onReady();
    latest.onCapabilities?.call(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'each visit automatically locates without overwriting shared destination',
      (tester) async {
    final source = Source(pending: true), actions = Actions();
    await mount(tester, source, actions);
    expect(source.calls, 1);
    latest.onReady();
    await tester.pump();
    expect(source.calls, 1);
    source.completer.complete(const LatLng(12, 105));
    await tester.pumpAndSettle();
    expect(latest.selected, data.point);
    expect(latest.userLocation, const LatLng(12, 105));
    expect(latest.cameraTarget, latest.userLocation);
    await tester.tap(find.byTooltip('分享位置'));
    await tester.pumpAndSettle();
    expect(actions.shared, same(data));
    await tester
        .tap(find.byKey(const ValueKey('chat-location-detail-recenter')));
    await tester.pumpAndSettle();
    expect(latest.cameraTarget, isNull);
    expect(latest.selected, data.point);
    await tester
        .tap(find.byKey(const ValueKey('chat-location-detail-directions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在浏览器中获取路线'));
    await tester.pumpAndSettle();
    expect(actions.routed, same(data));
    expect(actions.routes, 1);
  });
  testWidgets(
      'denied GPS retains destination and sharing recovers after failure',
      (tester) async {
    final source = Source(pending: true), actions = Actions()..fail = true;
    await mount(tester, source, actions);
    source.completer
        .completeError(const ChatLocationException(ChatLocationFailure.denied));
    await tester.pumpAndSettle();
    expect(latest.selected, data.point);
    expect(latest.userLocation, isNull);
    await tester.tap(find.byTooltip('分享位置'));
    await tester.pumpAndSettle();
    actions.fail = false;
    await tester.tap(find.byTooltip('分享位置'));
    await tester.pumpAndSettle();
    expect(actions.shares, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('map style changes without replacing destination',
      (tester) async {
    await mount(tester, Source(), Actions());
    await tester.tap(find.byTooltip('地图类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('卫星地图'));
    await tester.pumpAndSettle();
    expect(latest.satellite, isTrue);
    expect(latest.selected, data.point);
  });
  testWidgets('GPS completion after disposal is ignored', (tester) async {
    final source = Source(pending: true);
    await mount(tester, source, Actions());
    await tester.pumpWidget(const SizedBox());
    source.completer.complete(const LatLng(12, 105));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 568), const Size(844, 390)]) {
      testWidgets('controls stay reachable dark=$dark size=$size large text',
          (tester) async {
        await mount(tester, Source(), Actions(),
            size: size, scale: 2, dark: dark);
        expect(tester.takeException(), isNull);
        final close = tester
            .getRect(find.byKey(const ValueKey('chat-location-detail-back')));
        final layers = tester.getRect(find.byTooltip('地图类型'));
        expect(layers.top, greaterThanOrEqualTo(close.bottom));
        final directions =
            find.byKey(const ValueKey('chat-location-detail-directions'));
        await tester.ensureVisible(directions);
        await tester.pumpAndSettle();
        expect(directions.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'map chrome uses floating liquid glass and releases press feedback',
      (tester) async {
    await mount(tester, Source(), Actions());
    final surfaces =
        tester.widgetList<LiquidGlassSurface>(find.byType(LiquidGlassSurface));
    expect(surfaces.length, greaterThanOrEqualTo(8));
    expect(
        surfaces.every((s) =>
            s.preferLiquid &&
            s.surface == NavigationGlassSurface.floating &&
            s.opacity! < .8),
        isTrue);
    final button = find.byKey(const ValueKey('chat-location-detail-recenter'));
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .any((s) => s.scale < 1),
        isTrue);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .every((s) => s.scale == 1),
        isTrue);
  });
  testWidgets(
      'reopening requests fresh GPS and late GPS preserves explicit recenter',
      (tester) async {
    final first = Source(pending: true);
    await mount(tester, first, Actions());
    await tester
        .tap(find.byKey(const ValueKey('chat-location-detail-recenter')));
    await tester.pump();
    first.completer.complete(const LatLng(12, 105));
    await tester.pumpAndSettle();
    expect(latest.cameraTarget, isNull);
    expect(latest.userLocation, const LatLng(12, 105));
    expect(latest.selected, data.point);
    await tester.pumpWidget(const SizedBox());
    final second = Source();
    await mount(tester, second, Actions());
    await tester.pumpAndSettle();
    expect(second.calls, 1);
    expect(latest.cameraTarget, const LatLng(12, 105));
  });
  test('shared links encode original WGS84 point', () {
    const actions = ChatLocationDetailActions();
    expect(actions.link(data).queryParameters['query'], '11.55,104.94');
    expect(actions.link(data, directions: true).queryParameters['destination'],
        '11.55,104.94');
  });
}
