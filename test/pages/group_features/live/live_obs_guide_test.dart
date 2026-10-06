import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/live/pages/live_push_page.dart';
import 'package:openim/pages/group_features/live/widgets/live_obs_guide.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim_common/openim_common.dart';

import 'live_test_support.dart';

const _guideAsset = 'assets/img/group_live_guide.webp';
const _previewOutput = String.fromEnvironment('GROUP_LIVE_GUIDE_PREVIEW');
bool _fontsLoaded = false;

Finder get _sheet => find.byType(LiveObsGuideSheet);
Finder get _guideImage => find.descendant(
    of: _sheet,
    matching: find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == _guideAsset));
Finder get _acknowledge =>
    find.descendant(of: _sheet, matching: find.text('我知道了'));
Finder get _guideScroll =>
    find.descendant(of: _sheet, matching: find.byType(Scrollable)).first;

Widget _launcher() => Scaffold(
    body: Center(
        child: Builder(
            builder: (context) => TextButton(
                onPressed: () =>
                    showLiveObsGuide(context, hint: '服务端提示不会替代 99chat 原教程图片'),
                child: const Text('直播教程')))));

Future<void> _mount(WidgetTester tester, Widget page,
    {Size size = const Size(375, 812),
    bool dark = false,
    TargetPlatform platform = TargetPlatform.android,
    GlobalKey? boundaryKey}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  await tester.pumpWidget(RepaintBoundary(
      key: boundaryKey,
      child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
              debugShowCheckedModeBanner: false,
              translations: TranslationService(),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              theme: ThemeData(
                  platform: platform,
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: _fontsLoaded ? 'LiveGuidePreview' : null,
                  scaffoldBackgroundColor: AppTokens.background(dark: dark)),
              home: page))));
  await tester.pump();
  final context = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(() async {
    for (final asset in [
      _guideAsset,
      LiveStyle.backgroundAsset,
      LiveStyle.heroAsset
    ]) {
      if (!context.mounted) return;
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _open(WidgetTester tester) async {
  final trigger = find.text('直播教程');
  await tester.ensureVisible(trigger);
  await tester.tap(trigger);
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
}

Future<void> _reachButton(WidgetTester tester) async {
  await tester.scrollUntilVisible(_acknowledge, 180,
      scrollable: _guideScroll, maxScrolls: 30);
  await tester.pumpAndSettle();
  expect(_acknowledge.hitTestable(), findsOneWidget);
}

void _expectArtAndChrome(WidgetTester tester) {
  expect(_guideImage, findsOneWidget);
  final image = tester.widget<Image>(_guideImage);
  expect(image.fit, BoxFit.contain);
  final painted = tester.widget<RawImage>(
      find.descendant(of: _guideImage, matching: find.byType(RawImage)));
  expect(painted.image, isNotNull);
  expect(painted.image!.width, greaterThan(0));
  expect(painted.image!.height, greaterThan(0));
  final handle = find.descendant(
      of: _sheet,
      matching: find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.constraints?.maxWidth == 36 &&
          widget.constraints?.maxHeight == 4));
  expect(handle, findsOneWidget);
  expect(tester.getSize(handle), const Size(36, 4));
  final sheet = tester.getRect(_sheet);
  final imageRect = tester.getRect(_guideImage);
  expect(imageRect.left - sheet.left, closeTo(16, .01));
  expect(sheet.right - imageRect.right, closeTo(16, .01));
  final handleRect = tester.getRect(handle);
  expect(handleRect.center.dx, closeTo(sheet.center.dx, .01));
  expect(handleRect.top - sheet.top, closeTo(8, .01));
  expect(imageRect.top - handleRect.bottom, closeTo(12, .01));
  final button = find.ancestor(
      of: _acknowledge,
      matching:
          find.byWidgetPredicate((widget) => widget is ButtonStyleButton));
  expect(tester.getRect(button).top - imageRect.bottom, closeTo(16, .01));
  final background = find.descendant(
      of: _sheet,
      matching: find.byWidgetPredicate((widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).image?.image is AssetImage &&
          ((widget.decoration as BoxDecoration).image!.image as AssetImage)
                  .assetName ==
              LiveStyle.backgroundAsset));
  expect(background, findsOneWidget);
}

void _expectButton(WidgetTester tester) {
  final button = find.ancestor(
      of: _acknowledge,
      matching:
          find.byWidgetPredicate((widget) => widget is ButtonStyleButton));
  expect(button, findsOneWidget);
  expect(tester.getSize(button).height, 48);
  final style = tester.widget<ButtonStyleButton>(button).style!;
  expect(style.backgroundColor!.resolve({}), LiveStyle.blue);
  final shape = style.shape!.resolve({})! as RoundedRectangleBorder;
  expect(shape.borderRadius, BorderRadius.circular(24));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });

  for (final dark in [false, true]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
          'reference guide art and button open and dismiss (${platform.name}, ${dark ? 'dark' : 'light'})',
          (tester) async {
        await _mount(tester, _launcher(), dark: dark, platform: platform);
        await _open(tester);
        _expectArtAndChrome(tester);
        expect(tester.getSize(_sheet).height, lessThanOrEqualTo(812 * .85 + 1));
        await _reachButton(tester);
        _expectButton(tester);
        await tester.tap(_acknowledge);
        await tester.pumpAndSettle();
        expect(_sheet, findsNothing);
        expect(find.text('直播教程'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({platform}));
    }
  }

  for (final close in ['barrier', 'back']) {
    testWidgets('$close dismisses guide and leaves underlying route intact',
        (tester) async {
      await _mount(tester, _launcher());
      await _open(tester);
      if (close == 'barrier') {
        await tester.tapAt(const Offset(8, 8));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(find.text('直播教程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));
  }

  for (final size in [const Size(320, 568), const Size(640, 320)]) {
    testWidgets('long guide scrolls safely to acknowledge on $size',
        (tester) async {
      await _mount(tester, _launcher(), size: size);
      await _open(tester);
      final rect = tester.getRect(_sheet);
      expect(rect.height, lessThanOrEqualTo(size.height * .85 + 1));
      expect(rect.width, lessThanOrEqualTo(size.width));
      final scrollable = tester.state<ScrollableState>(_guideScroll);
      if (size.width > size.height) {
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
      } else {
        expect(scrollable.position.maxScrollExtent, greaterThanOrEqualTo(0));
      }
      await _reachButton(tester);
      _expectButton(tester);
      await tester.tap(_acknowledge);
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));
  }

  testWidgets('desktop guide is centered and constrained to reference width',
      (tester) async {
    const size = Size(1200, 900);
    await _mount(tester, _launcher(),
        size: size, platform: TargetPlatform.windows);
    await _open(tester);
    final rect = tester.getRect(_sheet);
    expect(rect.width, lessThanOrEqualTo(420));
    expect(rect.height, lessThanOrEqualTo(size.height * .82 + 1));
    expect(rect.center.dx, closeTo(size.width / 2, .5));
    expect(rect.center.dy, closeTo(size.height / 2, .5));
    _expectArtAndChrome(tester);
    await _reachButton(tester);
    await tester.tap(_acknowledge);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('actual push tutorial opens without another live request',
      (tester) async {
    final transport = _pushTransport();
    await _mount(
        tester,
        LivePushPage(
            featureContext: liveContext(transport.api()),
            session: liveSession()));
    final requests = transport.requests.length;
    await _open(tester);
    _expectArtAndChrome(tester);
    await _reachButton(tester);
    await tester.tap(_acknowledge);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.byType(LivePushPage), findsOneWidget);
    expect(transport.requests, hasLength(requests));
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('export real guide popup above push page in light and dark',
      (tester) async {
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
    try {
      await tester.runAsync(() async {
        for (final path in [
          'C:/Windows/Fonts/msyh.ttf',
          'C:/Windows/Fonts/msyh.ttc'
        ]) {
          final file = File(path);
          if (!await file.exists()) continue;
          await (FontLoader('LiveGuidePreview')
                ..addFont(file.readAsBytes().then(ByteData.sublistView)))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          _fontsLoaded = true;
          break;
        }
      });
      for (final dark in [false, true]) {
        final boundaryKey = GlobalKey();
        final transport = _pushTransport();
        await _mount(
            tester,
            LivePushPage(
                featureContext: liveContext(transport.api()),
                session: liveSession()),
            dark: dark,
            boundaryKey: boundaryKey);
        await _open(tester);
        _expectArtAndChrome(tester);
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('$_previewOutput-${dark ? 'dark' : 'light'}.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    } finally {
      debugDisableShadows = oldShadows;
    }
  },
      skip: _previewOutput.isEmpty,
      variant: const TargetPlatformVariant({TargetPlatform.android}));
}

LiveTransport _pushTransport() =>
    LiveTransport((request) => request.path.endsWith('/push-info')
        ? {
            'rtmpServer': 'rtmp://push.example.test/live',
            'streamKey': 'preview-stream-key',
            'expiresAt': DateTime.utc(2030).toIso8601String(),
            'obsHint': '复制地址与密钥到 OBS 后开始推流。'
          }
        : liveDTO());
