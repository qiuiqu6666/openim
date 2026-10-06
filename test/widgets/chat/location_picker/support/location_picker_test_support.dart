import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_location_test_source.dart';
import 'location_street_map_fixture.dart';
export 'chat_location_test_source.dart';

typedef LocationTestResult = ({
  double latitude,
  double longitude,
  String description
});

Finder locationKey(String suffix) =>
    find.byKey(ValueKey('chat-location-$suffix'));

void resumeLocationTestApp(WidgetTester tester) {
  final binding = tester.binding;
  while (binding.lifecycleState != AppLifecycleState.resumed) {
    final next = switch (binding.lifecycleState) {
      AppLifecycleState.paused => AppLifecycleState.hidden,
      AppLifecycleState.hidden => AppLifecycleState.inactive,
      _ => AppLifecycleState.resumed,
    };
    binding.handleAppLifecycleStateChanged(next);
  }
}

void pauseLocationTestApp(WidgetTester tester) {
  resumeLocationTestApp(tester);
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

final exportLocationPreviews =
    const bool.fromEnvironment('EXPORT_CHAT_LOCATION_PREVIEWS') ||
        Platform.environment['EXPORT_CHAT_LOCATION_PREVIEWS']?.toLowerCase() ==
            'true';
const locationPreviewFont = 'ChatLocationPreviewCjk';

Future<void> loadLocationPreviewFonts() async {
  if (!exportLocationPreviews) return;
  for (final entry in {
    locationPreviewFont: 'C:/Windows/Fonts/msyh.ttc',
    'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    await (FontLoader(entry.key)
          ..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes()))))
        .load();
  }
}

class LocationPickerHarness {
  LocationPickerHarness({LocationTestSource? source})
      : source = source ?? LocationTestSource();

  final LocationTestSource source;
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();
  LatLng? selectedFromMap;
  LocationTestResult? result;
  bool returned = false;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(393, 852),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    final oldDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    addTearDown(() => Styles.isDark = oldDark);
    Get.testMode = true;
    addTearDown(Get.reset);
    resumeLocationTestApp(tester);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        navigatorKey: navigator,
        locale: const Locale('zh', 'CN'),
        translations: TranslationService(),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
            brightness: brightness,
            fontFamily: exportLocationPreviews ? locationPreviewFont : null),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: Scaffold(
            body: Center(
                child: FilledButton(
          key: const ValueKey('open-location-fixture'),
          onPressed: () async {
            result = await navigator.currentState!.push<LocationTestResult>(
              MaterialPageRoute(
                  builder: (_) => ChatLocationPicker(
                      locationSource: source,
                      mapBuilder: (context, options) =>
                          LocationStreetMapFixture(
                            center: options.selected ??
                                const LatLng(22.543096, 114.057865),
                            enabled: options.active,
                            onReady: options.onReady,
                            onSelected: (point) {
                              selectedFromMap = point;
                              options.onSelected(point);
                            },
                          ))),
            );
            returned = true;
          },
          child: const Text('打开位置测试'),
        ))),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open-location-fixture')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
  }

  LatLng center(WidgetTester tester) => selectedFromMap!;

  Future<void> selectMapPoint(WidgetTester tester) async {
    final rect = tester.getRect(locationKey('map'));
    await tester
        .tapAt(rect.center + Offset(rect.width * .12, rect.height * .08));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> close(WidgetTester tester) async {
    resumeLocationTestApp(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> export(WidgetTester tester, String name) async {
    if (!exportLocationPreviews) return;
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('.temp/chat-location-picker')
          ..createSync(recursive: true);
        await File('${directory.path}/chat-location-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        await File('${directory.path}/preview-notes.txt').writeAsString(
          '真实 ChatLocationPicker Flutter 页面；原生地图 surface 由 mapBuilder 注入本地街道画布替身。\n'
          '定位数据仅来自测试夹具，无地图网络请求、权限请求或真实 GPS。\n'
          '亮/暗 393×852、小屏 320×640 大字 2 倍、短屏 393×393 大字 2 倍、横屏 852×393。\n'
          '键盘仅模拟 Flutter viewInsets，系统键盘本身未绘制进截图。\n'
          '导出加载 Microsoft YaHei 与项目 Flutter SDK 的原 MaterialIcons 字体。\n',
        );
      } finally {
        image.dispose();
      }
    });
  }
}
