import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

import '../../support/performance/render_test_fakes.dart';

class _ReadyFile extends Fake implements File {
  _ReadyFile(this.bytes);
  final Uint8List bytes;
  @override
  String get path => 'hero-ready.png';
  @override
  Future<bool> exists() async => true;
  @override
  Future<int> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
}

class _ViewerImage extends ViewerImageProvider {
  _ViewerImage(super.url, this.completer);
  final ImageStreamCompleter completer;
  @override
  ImageStreamCompleter loadImage(
          ViewerImageProvider key, ImageDecoderCallback decode) =>
      completer;
}

class _MissingFile extends Fake implements File {
  @override
  String get path => 'missing-gallery-photo.png';
  @override
  Future<bool> exists() async => false;
  @override
  Future<int> length() async => 0;
}

void main() {
  testWidgets('idle gallery only decodes the two immediate preview neighbors',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
    final picture = recorder.endRecording();
    final pixels = picture.toImageSync(12, 24);
    picture.dispose();
    addTearDown(pixels.dispose);
    final warmed = <String>{};
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 4,
      sources: List.generate(
          9,
          (i) => MediaSource(
              url: 'https://images.test/$i',
              thumbnail: 'https://images.test/$i')),
      imageProviderFactory: (url, budget) {
        if (budget == 375 * 812) warmed.add(url);
        return _ViewerImage(
            url,
            OneFrameImageStreamCompleter(
                SynchronousFuture(ImageInfo(image: pixels.clone()))));
      },
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(warmed, {'https://images.test/3', 'https://images.test/5'});
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('small drag paints incoming pixels when local preview is missing',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundaryKey = GlobalKey();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF00FF00), BlendMode.src);
    final picture = recorder.endRecording();
    final green = picture.toImageSync(375, 812);
    picture.dispose();
    addTearDown(green.dispose);
    final changes = <int>[];
    await tester.pumpWidget(renderTestHost(RepaintBoundary(
      key: boundaryKey,
      child: MediaBrowser(
        initialIndex: 0,
        sources: [
          MediaSource(
              url: 'https://test/first', thumbnail: 'https://test/first'),
          MediaSource(
              url: 'https://test/next',
              thumbnail: 'https://test/thumb',
              file: _MissingFile()),
        ],
        onPageChanged: changes.add,
        imageProviderFactory: (url, _) => _ViewerImage(
            url,
            OneFrameImageStreamCompleter(
                SynchronousFuture(ImageInfo(image: green.clone())))),
      ),
    )));
    await tester.pump();
    final drag = await tester.startGesture(const Offset(190, 400));
    for (final dx in [-5.0, -30.0, -45.0]) {
      await drag.moveBy(Offset(dx, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    final pager = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    expect(pager.controller.offset, inExclusiveRange(8, 187));
    expect(changes, isEmpty);
    final rgba = await tester.runAsync(() async {
      final frame = await (boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.dispose();
      return data!;
    });
    final pixel = (400 * 375 + 365) * 4;
    expect(rgba!.getUint8(pixel + 1), 255,
        reason:
            'Incoming image pixels must be visible, not just a mounted widget');
    expect(rgba.getUint8(pixel), 0);
    await drag.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('warmed arriving page stays visible while original is pending',
      (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
    final picture = recorder.endRecording();
    final pixels = picture.toImageSync(120, 240);
    picture.dispose();
    addTearDown(pixels.dispose);
    final original = Completer<ImageInfo>();
    final changes = <int>[];
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: List.generate(
          2,
          (i) => MediaSource(
              url: 'https://images.test/$i',
              thumbnail: 'https://images.test/$i')),
      onPageChanged: changes.add,
      imageProviderFactory: (url, budget) => _ViewerImage(
        url,
        OneFrameImageStreamCompleter(
          url.endsWith('/1') && budget == 16 * 1024 * 1024
              ? original.future
              : SynchronousFuture(ImageInfo(image: pixels.clone())),
        ),
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    final drag = await tester.startGesture(const Offset(400, 300));
    await drag.moveBy(const Offset(-5, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await drag.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await drag.moveBy(const Offset(-160, 0));
    await tester.pump();
    expect(changes, isEmpty,
        reason: 'Inspect the incoming page before halfway');
    expect(find.byWidgetPredicate((w) => w is ExtendedImageGesture),
        findsNWidgets(2),
        reason: 'Both sides of the swipe paint decoded pixels');
    await drag.moveBy(const Offset(-450, 0));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(changes, [1]);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(
        find.byWidgetPredicate((w) => w is ExtendedImageGesture), findsWidgets);
    original.complete(ImageInfo(image: pixels.clone()));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byWidgetPredicate((w) => w is ExtendedImageGesture),
          findsWidgets);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final interrupt in [false, true]) {
    testWidgets(
        interrupt
            ? 'opening picture can be dismissed before the flight completes'
            : 'local picture never returns to loading when opening flight ends',
        (tester) async {
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(120, 2400);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      }))!;
      final file = _ReadyFile(bytes);
      late BuildContext pageContext;
      await tester.pumpWidget(renderTestHost(Builder(builder: (context) {
        pageContext = context;
        return Center(
          child: Hero(
            tag: 'picture',
            placeholderBuilder: (_, __, child) => child,
            child: ExtendedImage.file(file,
                width: 120,
                height: 200,
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter),
          ),
        );
      })));
      await tester.runAsync(
          () => precacheImage(ExtendedFileImageProvider(file), pageContext));

      Navigator.of(pageContext).push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, __, ___) => MediaBrowser(
          initialIndex: 0,
          sources: [MediaSource(file: file, thumbnail: '', tag: 'picture')],
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(Duration(milliseconds: interrupt ? 100 : 290));
      expect(find.byWidgetPredicate((widget) => widget is ExtendedImageGesture),
          findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);

      if (!interrupt) {
        // Inspect the handoff frame itself, before another pump can hide a flash.
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(
            find.byWidgetPredicate((widget) => widget is ExtendedImageGesture),
            findsOneWidget);
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(CupertinoActivityIndicator), findsNothing,
              reason: 'No loading flash on handoff frame $frame');
          expect(
              find.byWidgetPredicate(
                  (widget) => widget is ExtendedImageGesture),
              findsOneWidget);
        }
      }
      Navigator.of(pageContext).pop();
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.byType(ExtendedImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('network thumbnail and original keep the same long image crop',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
    final picture = recorder.endRecording();
    final thumb = picture.toImageSync(120, 2400);
    final original = picture.toImageSync(240, 4800);
    picture.dispose();
    addTearDown(thumb.dispose);
    addTearDown(original.dispose);

    const originalUrl = 'https://media.example.test/original.png';
    const thumbnailUrl = 'https://media.example.test/thumbnail.png';
    final pending = Completer<ImageInfo>();
    final originalProvider =
        _ViewerImage(originalUrl, OneFrameImageStreamCompleter(pending.future));
    final thumbnailProvider = _ViewerImage(
        thumbnailUrl,
        OneFrameImageStreamCompleter(
            SynchronousFuture(ImageInfo(image: thumb.clone()))));

    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: [MediaSource(url: originalUrl, thumbnail: thumbnailUrl)],
      imageProviderFactory: (url, _) =>
          url == originalUrl ? originalProvider : thumbnailProvider,
    )));
    await tester.pump();
    final preview = tester
        .state<ExtendedImageGestureState>(
            find.byWidgetPredicate((widget) => widget is ExtendedImageGesture))
        .gestureDetails!
        .destinationRect!;
    expect(preview.left, closeTo(0, .01));
    expect(preview.top, closeTo(0, .01));
    expect(preview.width, closeTo(375, .01));

    pending.complete(ImageInfo(image: original.clone()));
    await tester.pump();
    await tester.pump();
    final loaded = tester
        .state<ExtendedImageGestureState>(
            find.byWidgetPredicate((widget) => widget is ExtendedImageGesture))
        .gestureDetails!
        .destinationRect!;
    expect(loaded, rectMoreOrLessEquals(preview, epsilon: .01),
        reason: 'The sharper original must not change the displayed crop');
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
