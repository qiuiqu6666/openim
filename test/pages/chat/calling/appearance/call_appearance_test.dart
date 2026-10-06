import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// ControlsView's public stream uses the live package's transitive Room type.
// ignore: depend_on_referenced_packages
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/pages/single/widgets/controls.dart';
import 'package:openim_live/src/widgets/call_surface/call_full_screen_surface.dart';
import 'package:openim_live/src/widgets/live_button.dart';

const _preview = bool.fromEnvironment('CALL_APPEARANCE_PREVIEW');
const _boundaryKey = ValueKey('call-appearance-preview');
const _background = Color(0xFF2D2D2D);
const _longName = '这是联系人备注名称和需要正确显示的很长昵称';

Widget _host(Widget child, {bool dark = false, double scale = 1}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: _preview ? 'CallAppearancePreviewFont' : null,
        ),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: RepaintBoundary(
          key: _boundaryKey,
          child: Scaffold(body: child),
        ),
      ),
    );

ControlsView _controls({
  CallState state = CallState.call,
  CallType type = CallType.audio,
  bool connected = false,
  String nickname = 'dual',
  Future<void> Function(bool)? microphone,
  Future<void> Function(bool)? speaker,
  VoidCallback? minimize,
}) =>
    ControlsView(
      key: ValueKey((state, type, connected)),
      initState: state,
      callType: type,
      connected: connected,
      callStateStream: const Stream<CallState>.empty(),
      roomDidUpdateStream: const Stream<Room>.empty(),
      userInfo: UserInfo(userID: 'peer', nickname: nickname),
      duration: 73,
      onPickUp: () {},
      onReject: () {},
      onCancel: () {},
      onHangUp: (_) {},
      onMinimize: minimize ?? () {},
      onPictureInPicture: () {},
      onSetMicrophone: microphone,
      onSetSpeaker: speaker,
    );

Finder _button(String label) => find.byWidgetPredicate(
    (widget) => widget is LiveButton && widget.text == label);

Future<void> _decodeControls(WidgetTester tester) async {
  final context = tester.element(find.byType(ControlsView));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  expect(images, isNotEmpty);
  await tester.runAsync(() async {
    await Future.wait(
        images.map((image) => precacheImage(image.image, context)));
  });
  await tester.pump(const Duration(milliseconds: 100));
  final rawImages = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
  expect(rawImages.length, greaterThanOrEqualTo(images.length));
  expect(rawImages.every((image) => image.image != null), isTrue);
}

Future<Uint8List> _pixels(WidgetTester tester, {String? preview}) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  boundary.markNeedsPaint();
  await tester.pump();
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (_preview && preview != null) {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('docs/previews/call-appearance-$preview.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void _expectDarkEdges(Uint8List rgba, int width, int height) {
  for (final (x, y) in [(1, 1), (1, height - 2), (width - 2, height - 2)]) {
    final offset = (y * width + x) * 4;
    expect(rgba.sublist(offset, offset + 4), [45, 45, 45, 255],
        reason: '通话背景必须覆盖安全区，不能露出普通页面背景');
  }
}

void _expectVisibleButtonImages(
    WidgetTester tester, Uint8List rgba, int width, int height) {
  for (final button in tester.widgetList<LiveButton>(find.byType(LiveButton))) {
    final image = find.descendant(
        of: find.byWidget(button), matching: find.byType(Image));
    expect(image, findsOneWidget);
    final rect = tester.getRect(image);
    expect(rect.width, greaterThan(40));
    expect(rect.height, greaterThan(40));
    var brightPixels = 0;
    var sampled = 0;
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        if (x < 0 || x >= width || y < 0 || y >= height) continue;
        sampled++;
        final offset = (y * width + x) * 4;
        if (rgba[offset] >= 215 &&
            rgba[offset + 1] >= 215 &&
            rgba[offset + 2] >= 215) {
          brightPixels++;
        }
      }
    }
    expect(brightPixels, greaterThan(sampled * .02),
        reason: '${button.text}必须在实际绘制结果中可见，不能只加载成功');
  }
}

void _expectAsset(LiveButton button, String path) {
  expect(button.icon, path);
  final image =
      find.descendant(of: find.byWidget(button), matching: find.byType(Image));
  expect(image, findsOneWidget);
  final provider = (image.evaluate().single.widget as Image).image;
  expect(provider, isA<AssetImage>());
  expect((provider as AssetImage).keyName, 'packages/openim_common/$path');
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance() + .05;
  final b = second.computeLuminance() + .05;
  return a > b ? a / b : b / a;
}

Color _compositedPixel(Uint8List data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return Color.alphaBlend(
      Color.fromARGB(data[i + 3], data[i], data[i + 1], data[i + 2]),
      _background);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_preview) return;
    final bytes = ByteData.sublistView(
        await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
    for (final family in [
      'CallAppearancePreviewFont',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  // Decode the bundled production images, rather than treating successful
  // widget construction or an unpainted first frame as proof of visible icons.
  for (final (label, asset) in [
    ('microphone on', ImageRes.liveMicOn),
    ('microphone off', ImageRes.liveMicOff),
    ('speaker on', ImageRes.liveSpeakerOn),
    ('speaker off', ImageRes.liveSpeakerOff),
    ('hang up', ImageRes.liveHangUp),
    ('pick up', ImageRes.livePicUp),
  ]) {
    testWidgets(
        '$label resource decodes with visible detail on call background',
        (tester) async {
      await tester.runAsync(() async {
        expect(asset, startsWith('assets/call_ui/'));
        final bytes = await rootBundle.load('packages/openim_common/$asset');
        final codec =
            await ui.instantiateImageCodec(bytes.buffer.asUint8List());
        try {
          final frame = await codec.getNextFrame();
          final image = frame.image;
          try {
            expect(image.width, greaterThanOrEqualTo(62));
            expect(image.height, greaterThanOrEqualTo(62));
            // Selected circles use 90% white and unselected circles 50% dark.
            // Read straight RGBA and composite; dropping alpha<230 would
            // falsely reject those valid semi-transparent button surfaces.
            final data = (await image.toByteData(
                    format: ui.ImageByteFormat.rawStraightRgba))!
                .buffer
                .asUint8List();
            var contrasting = 0;
            for (var i = 0; i < data.length; i += 4) {
              final color = Color.alphaBlend(
                  Color.fromARGB(
                      data[i + 3], data[i], data[i + 1], data[i + 2]),
                  _background);
              if (_contrast(color, _background) >= 3) contrasting++;
            }
            expect(contrasting, greaterThan(image.width * image.height * .02),
                reason: '按钮应在实际通话背景上可见，不能只有透明或低对比像素');
            if (label.startsWith('microphone') || label.startsWith('speaker')) {
              final circle = _compositedPixel(data, image.width,
                  image.width ~/ 2, (image.height * .12).round());
              var glyph = 0;
              // Exclude transparent corners and circle edges: this central
              // square measures the microphone/speaker glyph, not its circle.
              for (var y = (image.height * .3).ceil();
                  y < image.height * .7;
                  y++) {
                for (var x = (image.width * .3).ceil();
                    x < image.width * .7;
                    x++) {
                  final pixel = _compositedPixel(data, image.width, x, y);
                  if (_contrast(pixel, circle) >= 7) glyph++;
                }
              }
              expect(glyph, greaterThan(image.width * image.height * .02),
                  reason: '开关图标本身与圆形按钮底色必须有高对比，只有按钮背景不够');
            }
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      });
    });
  }

  for (final dark in [false, true]) {
    for (final state in [
      CallState.call,
      CallState.connecting,
      CallState.beCalled,
      CallState.calling,
    ]) {
      testWidgets(
          'actual audio surface $state has visible controls / dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(
          CallFullScreenSurface(
            child:
                _controls(state: state, connected: state == CallState.calling),
          ),
          dark: dark,
        ));
        await _decodeControls(tester);
        expect(find.text('dual'), findsOneWidget);
        expect(find.byType(AvatarView), findsOneWidget);
        expect(tester.widget<Text>(find.text('dual')).style!.color,
            AppTokens.onAccent);
        final status = switch (state) {
          CallState.call => StrRes.waitingVoiceCallHint,
          CallState.connecting => StrRes.connecting,
          CallState.beCalled => StrRes.invitedVoiceCallHint,
          _ => IMUtils.seconds2HMS(73),
        };
        expect(find.text(status), findsOneWidget);
        final secondary = tester.widget<Text>(find.text(status)).style!.color!;
        expect((secondary.a - .72).abs(), lessThan(.01));
        final blended = Color.alphaBlend(secondary, _background);
        expect(
            (blended.computeLuminance() + .05) /
                (_background.computeLuminance() + .05),
            greaterThan(4.5));
        for (final button
            in tester.widgetList<LiveButton>(find.byType(LiveButton))) {
          expect(button.foreground, AppTokens.onAccent);
          expect(button.onTap, isNotNull,
              reason: '连接中仅接听按钮禁用，音频通话挂断和媒体操作应仍可使用');
        }
        final regions = tester
            .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(find.descendant(
                of: find.byType(CallFullScreenSurface),
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)));
        expect(regions, hasLength(1));
        final bars = regions.single.value;
        expect(bars.statusBarIconBrightness, Brightness.light);
        expect(bars.statusBarBrightness, Brightness.dark);
        expect(bars.systemNavigationBarIconBrightness, Brightness.light);
        final pixels = await _pixels(tester,
            preview: state == CallState.call
                ? (dark ? 'dark-waiting' : 'light-waiting')
                : null);
        _expectDarkEdges(pixels, 375, 812);
        _expectVisibleButtonImages(tester, pixels, 375, 812);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }

    testWidgets('320px / 2x text / safe area retains call actions / dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      for (final state in [
        CallState.call,
        CallState.connecting,
        CallState.beCalled,
        CallState.calling,
      ]) {
        await tester.pumpWidget(_host(
          CallFullScreenSurface(
            child: _controls(
                state: state,
                connected: state == CallState.calling,
                nickname: _longName),
          ),
          dark: dark,
          scale: 2,
        ));
        await _decodeControls(tester);
        expect(find.text(_longName), findsOneWidget);
        for (final button
            in tester.widgetList<LiveButton>(find.byType(LiveButton))) {
          final rect = tester.getRect(find.byWidget(button));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.bottom, lessThanOrEqualTo(616));
          expect(
              tester
                  .widget<Text>(find.descendant(
                      of: find.byWidget(button), matching: find.byType(Text)))
                  .style!
                  .color,
              AppTokens.onAccent);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });
  }

  testWidgets(
      'microphone and speaker toggle real assets and preserve callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final microphones = <bool>[];
    final speakers = <bool>[];
    await tester.pumpWidget(_host(CallFullScreenSurface(
      child: _controls(
        microphone: (value) async => microphones.add(value),
        speaker: (value) async => speakers.add(value),
      ),
    )));
    await _decodeControls(tester);
    _expectAsset(tester.widget<LiveButton>(_button(StrRes.microphone)),
        ImageRes.liveMicOn);
    _expectAsset(tester.widget<LiveButton>(_button(StrRes.speaker)),
        ImageRes.liveSpeakerOff);
    await tester.tap(_button(StrRes.microphone));
    await tester.pump();
    await _decodeControls(tester);
    expect(microphones, [false]);
    _expectAsset(tester.widget<LiveButton>(_button(StrRes.microphone)),
        ImageRes.liveMicOff);
    _expectAsset(tester.widget<LiveButton>(_button(StrRes.speaker)),
        ImageRes.liveSpeakerOff);
    final mutedPixels = await _pixels(tester, preview: 'muted-speaker-off');
    _expectVisibleButtonImages(tester, mutedPixels, 375, 812);
    await tester.tap(_button(StrRes.speaker));
    await tester.pump();
    await _decodeControls(tester);
    expect(speakers, [true]);
    _expectAsset(tester.widget<LiveButton>(_button(StrRes.speaker)),
        ImageRes.liveSpeakerOn);
    await tester.tap(_button(StrRes.microphone));
    await tester.tap(_button(StrRes.speaker));
    await tester.pump();
    await _decodeControls(tester);
    expect(microphones, [false, true]);
    expect(speakers, [true, false]);
    _expectAsset(tester.widget<LiveButton>(_button(StrRes.microphone)),
        ImageRes.liveMicOn);
    _expectAsset(tester.widget<LiveButton>(_button(StrRes.speaker)),
        ImageRes.liveSpeakerOff);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving full-screen surface removes local system bar override',
      (tester) async {
    var fullScreen = true;
    await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
      return fullScreen
          ? CallFullScreenSurface(
              child:
                  _controls(minimize: () => setState(() => fullScreen = false)),
            )
          : const Center(child: Text('聊天页面'));
    })));
    await _decodeControls(tester);
    expect(find.byType(AppSystemBars), findsOneWidget);
    await tester.tap(find.byTooltip('最小化'));
    await tester.pump();
    expect(find.byType(CallFullScreenSurface), findsNothing);
    expect(find.byType(AppSystemBars), findsNothing);
    expect(find.text('聊天页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
