import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

final _pngs = <String, Uint8List>{};
const _shapes = <String, Size>{
  'wide': Size(320, 160),
  'tall': Size(160, 320),
  'square': Size(300, 300),
  'small': Size(40, 20),
  'long-wide': Size(3000, 100),
  'long-tall': Size(100, 3000),
};
const _expectedSizes = <String, Size>{
  'wide': Size(144, 72),
  'tall': Size(92, 160),
  'square': Size(144, 144),
  'small': Size(144, 72),
  'long-wide': Size(144, 144 / 30),
  'long-tall': Size(92, 160),
};

Future<Uint8List> _png(Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF168BFF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

// Two colored 1x1 frames, a 100 ms delay, and an infinite GIF loop.
Uint8List _gif() => Uint8List.fromList([
      ...ascii.encode('GIF89a'),
      1,
      0,
      1,
      0,
      0x80,
      0,
      0,
      0xFF,
      0,
      0,
      0,
      0,
      0xFF,
      0x21,
      0xFF,
      11,
      ...ascii.encode('NETSCAPE2.0'),
      3,
      1,
      0,
      0,
      0,
      0x21,
      0xF9,
      4,
      4,
      10,
      0,
      0,
      0,
      0x2C,
      0,
      0,
      0,
      0,
      1,
      0,
      1,
      0,
      0,
      2,
      2,
      0x44,
      1,
      0,
      0x21,
      0xF9,
      4,
      4,
      10,
      0,
      0,
      0,
      0x2C,
      0,
      0,
      0,
      0,
      1,
      0,
      1,
      0,
      0,
      2,
      2,
      0x4C,
      1,
      0,
      0x3B,
    ]);

class _DeferredImage extends ImageProvider<_DeferredImage> {
  final data = Completer<Uint8List>();

  @override
  Future<_DeferredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _DeferredImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: data.future.then((bytes) async =>
            decode(await ui.ImmutableBuffer.fromUint8List(bytes))),
        scale: 1,
      );
}

Future<void> _flush(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double screenWidth = 375,
  double screenHeight = 812,
}) async {
  tester.view.physicalSize = Size(screenWidth, screenHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Builder(
          builder: (context) => ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  ));
  await _flush(tester);
}

void _expectSize(WidgetTester tester, Size expected,
    {Finder? finder, String? reason}) {
  final actual = tester.getSize(finder ?? find.byType(ChatImageSticker));
  expect(actual.width, closeTo(expected.width, 0.01), reason: reason);
  expect(actual.height, closeTo(expected.height, 0.01), reason: reason);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flush(tester);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in _shapes.entries) {
      _pngs[entry.key] = await _png(entry.value);
    }
    final codec = await ui.instantiateImageCodec(_gif());
    expect(codec.frameCount, 2);
    codec.dispose();
  });
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    testWidgets('failed image retains its known bounds in $brightness',
        (tester) async {
      final failed = _DeferredImage();
      await _mount(
          tester,
          ChatImageSticker(
              url: 'failed-$brightness',
              intrinsicSize: _shapes['wide'],
              imageProvider: failed),
          brightness: brightness);
      _expectSize(tester, _expectedSizes['wide']!);
      failed.data.complete(Uint8List.fromList([0, 1, 2]));
      await _flush(tester);
      _expectSize(tester, _expectedSizes['wide']!);
      final error = find.byIcon(Icons.emoji_emotions_outlined);
      expect(error, findsOneWidget);
      expect(tester.widget<Icon>(error).color,
          Theme.of(tester.element(error)).colorScheme.onSurfaceVariant);
      expect(tester.widget<Icon>(error).size, closeTo(72 * 0.3, 0.01));
      final placeholder =
          find.ancestor(of: error, matching: find.byType(ColoredBox)).first;
      expect(
          tester.widget<ColoredBox>(placeholder).color,
          Theme.of(tester.element(error))
              .colorScheme
              .onSurface
              .withValues(alpha: 0.12));
      await _unmount(tester);
    });

    testWidgets(
        'unknown images keep the tier placeholder after failure in $brightness',
        (tester) async {
      final failed = _DeferredImage();
      await _mount(
          tester,
          ChatImageSticker(
              url: 'unknown-failed-$brightness', imageProvider: failed),
          brightness: brightness);
      _expectSize(tester, const Size.square(144));
      failed.data.complete(Uint8List.fromList([0, 1, 2]));
      await _flush(tester);
      _expectSize(tester, const Size.square(144));
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _unmount(tester);
    });

    testWidgets(
        'image stickers match 99chat fit and crop frames in $brightness',
        (tester) async {
      for (final entry in _shapes.entries) {
        await _mount(
            tester,
            ChatImageSticker(
              url: 'metadata-${entry.key}-$brightness',
              intrinsicSize: entry.value,
              imageProvider: MemoryImage(_pngs[entry.key]!),
            ),
            brightness: brightness);
        _expectSize(tester, _expectedSizes[entry.key]!);
        final image = tester.widget<Image>(find.byType(Image));
        final cropped = entry.key == 'tall' || entry.key == 'long-tall';
        expect(image.fit, cropped ? BoxFit.cover : BoxFit.contain);
        expect(image.alignment, Alignment.center);
        final clip = tester.widget<ClipRRect>(find.descendant(
            of: find.byType(ChatImageSticker),
            matching: find.byType(ClipRRect)));
        expect(clip.borderRadius, BorderRadius.circular(6));
        expect(tester.takeException(), isNull);
      }
      await _unmount(tester);
    });
  }

  testWidgets(
      '320 wide screens honor a narrow parent without distorting images',
      (tester) async {
    await _mount(
        tester,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 80),
          child: ChatImageSticker(
              url: 'narrow-parent',
              intrinsicSize: _shapes['wide'],
              imageProvider: MemoryImage(_pngs['wide']!)),
        ),
        screenWidth: 320);
    _expectSize(tester, const Size(43.2, 21.6));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('screen dimensions select the 99chat phone and desktop tiers',
      (tester) async {
    const screens = <(Size, Size)>[
      (Size(320, 812), Size(132, 66)),
      (Size(375, 699), Size(132, 66)),
      (Size(375, 840), Size(156, 78)),
      (Size(800, 900), Size(260, 130)),
    ];
    for (final entry in screens) {
      await _mount(
          tester,
          ChatImageSticker(
              url: 'screen-${entry.$1}',
              intrinsicSize: _shapes['wide'],
              imageProvider: MemoryImage(_pngs['wide']!)),
          screenWidth: entry.$1.width,
          screenHeight: entry.$1.height);
      _expectSize(tester, entry.$2);
      expect(tester.takeException(), isNull);
    }
    await _unmount(tester);
  });

  testWidgets('old URL-only stickers use decoded first-frame dimensions',
      (tester) async {
    final image = _DeferredImage();
    await _mount(tester,
        ChatImageSticker(url: 'decoded-first-frame', imageProvider: image));
    _expectSize(tester, const Size.square(144));
    image.data.complete(_pngs['wide']!);
    await _flush(tester);
    _expectSize(tester, _expectedSizes['wide']!);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
    await _unmount(tester);

    final pending = _DeferredImage();
    await _mount(tester,
        ChatImageSticker(url: 'decoded-first-frame', imageProvider: pending));
    _expectSize(tester, _expectedSizes['wide']!,
        reason:
            'The same URL should reuse its known dimensions before loading.');
    await tester.pumpWidget(const SizedBox.shrink());
    pending.data.complete(_pngs['wide']!);
    await _flush(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'explicit dimensions take precedence over the decoded first frame',
      (tester) async {
    await _mount(
        tester,
        ChatImageSticker(
            url: 'metadata-precedence',
            intrinsicSize: _shapes['tall'],
            imageProvider: MemoryImage(_pngs['wide']!)));
    _expectSize(tester, _expectedSizes['tall']!);
    await _unmount(tester);
  });

  testWidgets('late old-URL frames cannot resize an updated sticker',
      (tester) async {
    final old = _DeferredImage();
    await _mount(
        tester, ChatImageSticker(url: 'pending-old-url', imageProvider: old));
    _expectSize(tester, const Size.square(144));
    await _mount(
        tester,
        ChatImageSticker(
            url: 'updated-new-url',
            imageProvider: MemoryImage(_pngs['tall']!)));
    _expectSize(tester, _expectedSizes['tall']!);
    old.data.complete(_pngs['wide']!);
    await _flush(tester);
    _expectSize(tester, _expectedSizes['tall']!);
    await _unmount(tester);
  });

  testWidgets(
      'first-frame completion after unloading does not update disposed state',
      (tester) async {
    final pending = _DeferredImage();
    await _mount(tester,
        ChatImageSticker(url: 'pending-dispose', imageProvider: pending));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.data.complete(_pngs['wide']!);
    await _flush(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GIF remains animated after first-frame size detection',
      (tester) async {
    await _mount(
        tester,
        ChatImageSticker(
            url: 'animated-gif', imageProvider: MemoryImage(_gif())));
    final first = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(first, isNotNull);
    _expectSize(tester, const Size.square(144));
    await tester.pump(const Duration(milliseconds: 120));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    final next = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(identical(first, next), isFalse);
    _expectSize(tester, const Size.square(144));
    await _unmount(tester);
  });
}
