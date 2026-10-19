import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/media/shared_image_disk_cache.dart';
import 'package:openim_common/src/widgets/media_browser/original_image_progress.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';

import '../../support/performance/render_test_fakes.dart';

class _Stream extends ImageStreamCompleter {
  void progress(int received, int? total) =>
      reportImageChunkEvent(ImageChunkEvent(
          cumulativeBytesLoaded: received, expectedTotalBytes: total));
  void complete(ui.Image image) => setImage(ImageInfo(image: image.clone()));
}

class _Image extends ViewerImageProvider {
  _Image(super.url);
  final stream = _Stream();
  @override
  ImageStreamCompleter loadImage(
          ViewerImageProvider key, ImageDecoderCallback decode) =>
      stream;
}

void main() {
  testWidgets('original shows byte sectors and reopens from persistent cache',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('original-reopen');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => temp.path);
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      temp.deleteSync(recursive: true);
    });
    const original = 'https://original.test/full';
    const preview = 'https://original.test/preview';
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final pixels = picture.toImageSync(20, 30);
    picture.dispose();
    addTearDown(pixels.dispose);
    final requests = <String, _Image>{};
    Widget browser() => renderTestHost(MediaBrowser(
          sources: [
            MediaSource(
                url: original,
                previewUrl: preview,
                thumbnail: preview,
                deferOriginal: true)
          ],
          initialIndex: 0,
          imageProviderFactory: (url, _) {
            final image = _Image(url);
            requests[url] = image;
            if (url == preview) image.stream.complete(pixels);
            return image;
          },
        ));
    await tester.runAsync(() async {
      await tester.pumpWidget(browser());
      expect(await ViewerImageProvider(original).isCached(), isFalse);
    });
    await tester.pump();
    expect(requests.containsKey(original), isTrue);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(OriginalImageProgress), findsOneWidget);
    final image = requests[original]!;
    image.stream.progress(25, 100);
    await tester.pump();
    expect(
        tester
            .widget<OriginalImageProgress>(find.byType(OriginalImageProgress))
            .progress,
        .25);
    image.stream.progress(80, 100);
    await tester.pump();
    expect(
        tester
            .widget<OriginalImageProgress>(find.byType(OriginalImageProgress))
            .progress,
        .8);
    // The download persists encoded data, not a process-local preference.
    await tester.runAsync(() => SharedImageDiskCache()
        .write(original, renderTestPng(), isCurrent: () => true));
    image.stream.complete(pixels);
    await tester.pump();
    expect(find.byType(OriginalImageProgress), findsNothing);
    await tester.pumpWidget(const SizedBox());
    requests.clear();
    await tester.runAsync(() async {
      expect(await ViewerImageProvider(original).isCached(), isTrue);
      await tester.pumpWidget(browser());
    });
    // Allow real filesystem lookups to complete outside the fake clock.
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(requests.containsKey(original), isTrue);
    expect(find.byType(TextButton), findsNothing);
    requests[original]!.stream.complete(pixels);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => DefaultCacheManager().dispose());
  });

  testWidgets('unknown length does not invent percentage, reduced motion works',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: OriginalImageProgress(
          event: ImageChunkEvent(
              cumulativeBytesLoaded: 20, expectedTotalBytes: null)),
    )));
    expect(
        tester
            .widget<OriginalImageProgress>(find.byType(OriginalImageProgress))
            .progress,
        isNull);
    expect(find.byIcon(Icons.downloading), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
