import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/media_browser/media_image_loading.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';

import '../../support/performance/render_test_fakes.dart';

class _ControlledStream extends ImageStreamCompleter {
  void complete(ui.Image image) => setImage(ImageInfo(image: image));
}

class _ControlledImage extends ViewerImageProvider {
  _ControlledImage(super.url);
  final stream = _ControlledStream();

  @override
  ImageStreamCompleter loadImage(
          ViewerImageProvider key, ImageDecoderCallback decode) =>
      stream;

  void fail() => stream.reportError(
        context: ErrorDescription('loading test image'),
        exception: StateError('preview unavailable'),
        silent: true,
      );
}

void main() {
  testWidgets('full-screen automatically upgrades thumbnail to original',
      (tester) async {
    final requests = <String, _ControlledImage>{};
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: [
        MediaSource(
            url: 'https://images.test/original',
            previewUrl: 'https://images.test/clear',
            thumbnail: 'https://images.test/thumb',
            deferOriginal: true)
      ],
      imageProviderFactory: (url, _) =>
          requests.putIfAbsent(url, () => _ControlledImage(url)),
    )));
    await tester.pump();
    expect(requests.keys, contains('https://images.test/original'));
    expect(find.byType(TextButton), findsNothing);
    ui.Image pixels(int size) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(size, size);
      picture.dispose();
      return image;
    }

    Finder displayed(int size) => find.byWidgetPredicate(
        (widget) => widget is ExtendedRawImage && widget.image?.width == size);
    requests['https://images.test/thumb']!.stream.complete(pixels(20));
    await tester.pump();
    expect(displayed(20), findsOneWidget);
    requests['https://images.test/clear']!.stream.complete(pixels(100));
    await tester.pump();
    expect(displayed(100), findsOneWidget);
    requests['https://images.test/original']!.fail();
    await tester.pump();
    expect(displayed(100), findsOneWidget);
    requests['https://images.test/original']!.stream.complete(pixels(200));
    await tester.pump();
    expect(displayed(200), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final succeeds in [true, false]) {
    testWidgets('cached thumbnail survives until clear preview: $succeeds',
        (tester) async {
      final requests = <String, _ControlledImage>{};
      ui.Image pixels(int size) {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(size, size);
        picture.dispose();
        return image;
      }

      await tester.pumpWidget(renderTestHost(MediaBrowser(
        autoLoadOriginal: false,
        initialIndex: 0,
        sources: [
          MediaSource(
            url: 'https://images.test/original',
            previewUrl: 'https://images.test/clear',
            thumbnail: 'https://images.test/thumb',
            deferOriginal: true,
          ),
        ],
        imageProviderFactory: (url, _) {
          final image = _ControlledImage(url);
          requests[url] = image;
          if (url.endsWith('/thumb')) image.stream.complete(pixels(20));
          return image;
        },
      )));
      await tester.pump();
      Finder imageAtSize(int size) => find.byWidgetPredicate((widget) =>
          widget is ExtendedRawImage && widget.image?.width == size);
      expect(imageAtSize(20), findsOneWidget);
      expect(find.byType(MediaImageLoading), findsNothing);
      expect(requests.keys.any((url) => url.endsWith('/original')), isFalse);

      final clear = requests['https://images.test/clear']!;
      if (succeeds) {
        clear.stream.complete(pixels(100));
      } else {
        clear.fail();
      }
      await tester.pump();
      expect(imageAtSize(succeeds ? 100 : 20), findsOneWidget);
      expect(find.byType(MediaImageLoading), findsNothing);
      expect(find.text('Failed to load image'), findsNothing);
      expect(find.byIcon(Icons.image_not_supported_outlined),
          succeeds ? findsNothing : findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('swiping past a failed preview keeps loading ($brightness)',
        (tester) async {
      final requests = <_ControlledImage>[];
      await tester.pumpWidget(renderTestHost(
        MediaBrowser(
          autoLoadOriginal: false,
          initialIndex: 0,
          sources: List.generate(
            2,
            (i) => MediaSource(
              url: 'https://images.test/full/$i',
              thumbnail: 'https://images.test/thumb/$i',
            ),
          ),
          imageProviderFactory: (url, _) {
            final image = _ControlledImage(url);
            requests.add(image);
            return image;
          },
        ),
        brightness: brightness,
      ));
      await tester.pump();
      await tester.drag(
          find.byType(ExtendedImageGesturePageView), const Offset(-700, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final thumbnail = requests.firstWhere((r) => r.url.endsWith('thumb/1'));
      thumbnail.fail();
      await tester.pump();
      expect(find.text('Failed to load image'), findsNothing);
      expect(find.byType(MediaImageLoading), findsWidgets);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);

      final full = requests.firstWhere((r) => r.url.endsWith('full/1'));
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final pixels = picture.toImageSync(20, 30);
      picture.dispose();
      full.stream.complete(pixels);
      await tester.pump();
      expect(find.text('Failed to load image'), findsNothing);
      expect(
          find.byWidgetPredicate(
              (widget) => widget is ExtendedRawImage && widget.image != null),
          findsWidgets);

      // An actual failure of the main image must still offer recovery.
      full.fail();
      await tester.pump();
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
