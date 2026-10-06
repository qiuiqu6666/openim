import 'dart:io';
import 'dart:ui' show ImageByteFormat, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

const _previewFont = String.fromEnvironment('CHAT_HINT_PREVIEW_FONT');

Future<void> _pump(
  WidgetTester tester,
  Widget view, {
  Locale locale = const Locale('zh', 'CN'),
  bool dark = false,
  Size size = const Size(375, 812),
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  Styles.isDark = dark;
  Get.locale = locale;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: locale,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: _previewFont.isEmpty ? null : 'ChatHintPreviewFont',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(body: view),
    ),
  ));
  await tester.pump();
}

Widget _watermark(
        {int count = 0,
        bool showBack = false,
        VoidCallback? onTap,
        Widget? bottomView}) =>
    WaterMarkBgView(
      newMessageCount: count,
      showBackToBottom: showBack,
      onSeeNewMessage: onTap,
      bottomView: bottomView,
      child: const SizedBox.expand(),
    );

Future<void> _savePreview(
    WidgetTester tester, GlobalKey boundaryKey, String path) async {
  if (!const bool.fromEnvironment('CHAT_HINT_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<Uint8List> _capturePixels(
    WidgetTester tester, GlobalKey boundaryKey) async {
  return (await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      return Uint8List.fromList(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_previewFont.isEmpty) return;
    final text = FontLoader('ChatHintPreviewFont')
      ..addFont(File(_previewFont)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await text.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  testWidgets('no indicator is added by default when there are no new messages',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, _watermark());
    expect(find.byType(NewMessageIndicator), findsNothing);
    expect(find.text('回到底部'), findsNothing);
  });

  testWidgets(
      'new message count takes precedence over the back-to-bottom label',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, _watermark(count: 3, showBack: true));
    expect(find.text('3条新消息'), findsOneWidget);
    expect(find.text('回到底部'), findsNothing);
  });

  testWidgets(
      'decreasing count switches to back-to-bottom and hides after reaching the bottom',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = ValueNotifier<(int, bool)>((3, true));
    addTearDown(state.dispose);
    var taps = 0;
    await _pump(
        tester,
        ValueListenableBuilder<(int, bool)>(
          valueListenable: state,
          builder: (_, value, __) => _watermark(
              count: value.$1, showBack: value.$2, onTap: () => taps++),
        ));
    expect(find.text('3条新消息'), findsOneWidget);
    state.value = (2, true);
    await tester.pump();
    expect(find.text('2条新消息'), findsOneWidget);
    expect(find.text('3条新消息'), findsNothing);
    state.value = (0, true);
    await tester.pump();
    expect(find.text('回到底部'), findsOneWidget);
    expect(find.text('0条新消息'), findsNothing);
    await tester.tap(find.byType(NewMessageIndicator));
    await tester.pump();
    expect(taps, 1);
    state.value = (0, false);
    await tester.pump();
    expect(find.byType(NewMessageIndicator), findsNothing);
  });

  for (final count in [0, 4]) {
    testWidgets('English indicator localizes count=$count', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, _watermark(count: count, showBack: true),
          locale: const Locale('en', 'US'));
      expect(find.text(count == 0 ? 'Back to bottom' : '4 New Messages'),
          findsOneWidget);
      expect(find.text('0 New Messages'), findsNothing);
    });
  }

  for (final count in [0, 3]) {
    testWidgets(
        'indicator has one accessible button and a 48dp hit target for count=$count',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        var taps = 0;
        await _pump(tester,
            _watermark(count: count, showBack: true, onTap: () => taps++));
        final label = count == 0 ? '回到底部' : '3条新消息';
        final button = find.bySemanticsLabel(label);
        expect(button, findsOneWidget);
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.hint, count == 0 ? '' : '回到底部');
        final hitTarget = find
            .descendant(
                of: find.byType(NewMessageIndicator),
                matching: find.byType(GestureDetector))
            .first;
        final rect = tester.getRect(hitTarget);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        // Tap outside the compact visual pill, inside the expanded hit area.
        await tester.tapAt(Offset(rect.center.dx, rect.top + 2));
        await tester.pump();
        expect(taps, 1);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
      'an indicator without a callback is disabled in accessibility semantics',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, _watermark(showBack: true));
      final data =
          tester.getSemantics(find.bySemanticsLabel('回到底部')).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    } finally {
      semantics.dispose();
    }
  });

  for (final count in [0, 42]) {
    testWidgets(
        'indicator meets the right edge with only its left end rounded count=$count',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      final boundaryKey = GlobalKey();
      await _pump(
          tester,
          RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: Styles.c_FFFFFF,
              child:
                  _watermark(count: count, showBack: true, onTap: () => taps++),
            ),
          ));
      final indicator = tester.getRect(find.byType(NewMessageIndicator));
      final inkFinder = find.descendant(
          of: find.byType(NewMessageIndicator), matching: find.byType(Ink));
      final ink = tester.widget<Ink>(inkFinder);
      final visual = tester.getRect(inkFinder);
      final decoration = ink.decoration! as BoxDecoration;
      final radius = decoration.borderRadius!.resolve(TextDirection.ltr);
      expect(indicator.right, closeTo(375, .01));
      expect(visual.right, closeTo(375, .01));
      expect(indicator.width, lessThan(375 / 2),
          reason:
              'The transparent button must stay compact at the right edge.');
      expect(radius.topLeft.x, greaterThanOrEqualTo(visual.height / 2));
      expect(radius.bottomLeft, radius.topLeft);
      expect(radius.topRight, Radius.zero);
      expect(radius.bottomRight, Radius.zero);
      final inkWell = tester.widget<InkWell>(find.descendant(
          of: find.byType(NewMessageIndicator),
          matching: find.byType(InkWell)));
      expect(inkWell.borderRadius, decoration.borderRadius);
      await tester.tapAt(Offset(indicator.right - 1, indicator.center.dy));
      await tester.pump();
      expect(taps, 1);
      await tester.tapAt(Offset(1, indicator.center.dy));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      await _savePreview(
          tester,
          boundaryKey,
          count == 0
              ? '.dart_tool/chat-hint-right-edge-back-preview.png'
              : '.dart_tool/chat-hint-right-edge-preview.png');
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
        'indicator has requested blue fill and white content dark=$dark',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, _watermark(showBack: true, onTap: () {}), dark: dark);
      final text = tester.widget<Text>(find.text('回到底部'));
      final ink = tester.widget<Ink>(find.descendant(
          of: find.byType(NewMessageIndicator), matching: find.byType(Ink)));
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.color, ChatScrollHintTokens.background);
      expect(decoration.border, isNull);
      expect(text.style?.color, ChatScrollHintTokens.foreground);
      expect(text.style?.fontSize, 14.sp);
      expect(text.style?.fontWeight, FontWeight.w600);
      final arrow = tester.widget<Icon>(find.descendant(
          of: find.byType(NewMessageIndicator),
          matching: find.byIcon(Icons.keyboard_double_arrow_down)));
      expect(arrow.color, ChatScrollHintTokens.foreground);
      expect(decoration.color, const Color(0xFF1296F6));
    });
  }

  for (final count in [0, 42]) {
    testWidgets('pressed feedback stays inside the blue surface count=$count',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      var taps = 0;
      await _pump(
          tester,
          RepaintBoundary(
            key: boundaryKey,
            child:
                _watermark(count: count, showBack: true, onTap: () => taps++),
          ),
          dark: count > 0);
      final surface = tester.getRect(find.descendant(
          of: find.byType(NewMessageIndicator), matching: find.byType(Ink)));
      final inkWellRect = tester.getRect(find.descendant(
          of: find.byType(NewMessageIndicator),
          matching: find.byType(InkWell)));
      expect(inkWellRect, surface);
      final before = await _capturePixels(tester, boundaryKey);
      final gesture = await tester.startGesture(surface.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 60));
      final pressed = await _capturePixels(tester, boundaryKey);
      var insideChanged = false;
      var outsideChanged = false;
      // Compare the painted pixels, including the transparent 48dp touch
      // margin and shadow. Only the actual blue surface may change on press.
      for (var y = 0; y < 812; y++) {
        for (var x = 0; x < 375; x++) {
          final index = (y * 375 + x) * 4;
          final changed = before[index] != pressed[index] ||
              before[index + 1] != pressed[index + 1] ||
              before[index + 2] != pressed[index + 2] ||
              before[index + 3] != pressed[index + 3];
          if (!changed) continue;
          if (surface.contains(Offset(x + .5, y + .5))) {
            insideChanged = true;
          } else {
            outsideChanged = true;
          }
        }
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(insideChanged, isTrue, reason: 'Keep the visible press feedback.');
      expect(outsideChanged, isFalse,
          reason: 'Do not paint press feedback in the shadow or touch margin.');
      expect(taps, 1,
          reason: 'The nested touch targets must trigger only once.');
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(375, 812),
    const Size(812, 375)
  ]) {
    testWidgets(
        'large text keeps the blue pill against the right chat edge ${size.width}x${size.height}',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
          tester, _watermark(count: 999999, showBack: true, onTap: () {}),
          size: size,
          textScale: 3,
          reduceMotion: true,
          locale: const Locale('en', 'US'));
      expect(tester.takeException(), isNull);
      expect(find.text('999999 New Messages'), findsOneWidget);
      final rect = tester.getRect(find.byType(NewMessageIndicator));
      expect(rect.left, greaterThanOrEqualTo(AppTokens.s4.w - .01));
      expect(rect.right, closeTo(size.width, .01));
      expect(rect.height, greaterThanOrEqualTo(48));
      final inkFinder = find.descendant(
          of: find.byType(NewMessageIndicator), matching: find.byType(Ink));
      final visual = tester.getRect(inkFinder);
      final decoration =
          tester.widget<Ink>(inkFinder).decoration! as BoxDecoration;
      final radius = decoration.borderRadius!.resolve(TextDirection.ltr);
      expect(visual.left, greaterThanOrEqualTo(AppTokens.s4.w - .01));
      expect(visual.right, closeTo(size.width, .01));
      expect(radius.topLeft.x, greaterThan(0));
      expect(radius.bottomLeft, radius.topLeft);
      expect(radius.topRight, Radius.zero);
      expect(radius.bottomRight, Radius.zero);
      expect(decoration.color, const Color(0xFF1296F6));
    });
  }

  testWidgets(
      'indicator stays above the bottom composer rather than covering it',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const composerKey = Key('composer');
    await _pump(
        tester,
        _watermark(
            showBack: true,
            onTap: () {},
            bottomView: const SizedBox(key: composerKey, height: 70)));
    final indicator = tester.getRect(find.byType(NewMessageIndicator));
    final composer = tester.getRect(find.byKey(composerKey));
    expect(indicator.bottom, lessThan(composer.top));
  });
}
