import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

void main() {
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
      expect(find.byType(ExtendedImageGesture), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);

      if (!interrupt) {
        // Inspect the handoff frame itself, before another pump can hide a flash.
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.byType(ExtendedImageGesture), findsOneWidget);
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(CupertinoActivityIndicator), findsNothing,
              reason: 'No loading flash on handoff frame $frame');
          expect(find.byType(ExtendedImageGesture), findsOneWidget);
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
        ExtendedNetworkImageProvider(originalUrl, cache: true);
    originalProvider.imageCache.putIfAbsent(
        originalProvider, () => OneFrameImageStreamCompleter(pending.future));
    final thumbnailProvider =
        ExtendedNetworkImageProvider(thumbnailUrl, cache: true);
    thumbnailProvider.imageCache.putIfAbsent(
        thumbnailProvider,
        () => OneFrameImageStreamCompleter(
            SynchronousFuture(ImageInfo(image: thumb.clone()))));

    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: [MediaSource(url: originalUrl, thumbnail: thumbnailUrl)],
    )));
    await tester.pump();
    final preview = tester
        .state<ExtendedImageGestureState>(find.byType(ExtendedImageGesture))
        .gestureDetails!
        .destinationRect!;
    expect(preview.left, closeTo(0, .01));
    expect(preview.top, closeTo(0, .01));
    expect(preview.width, closeTo(375, .01));

    pending.complete(ImageInfo(image: original.clone()));
    await tester.pump();
    await tester.pump();
    final loaded = tester
        .state<ExtendedImageGestureState>(find.byType(ExtendedImageGesture))
        .gestureDetails!
        .destinationRect!;
    expect(loaded, rectMoreOrLessEquals(preview, epsilon: .01),
        reason: 'The sharper original must not change the displayed crop');
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
