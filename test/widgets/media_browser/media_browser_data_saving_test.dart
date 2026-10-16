import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';
import '../../support/performance/render_test_fakes.dart';

class _Image extends ViewerImageProvider {
  _Image(super.url, this.pixels);
  final ui.Image pixels;
  @override
  ImageStreamCompleter loadImage(
          ViewerImageProvider key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: pixels.clone())));
}

void main() {
  for (final hasPreview in [true, false]) {
    testWidgets(
        'browser only requests original after explicit tap, preview=$hasPreview',
        (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final pixels = picture.toImageSync(20, 30);
      picture.dispose();
      final requests = <String>[];
      const original = 'https://image.test/original?signature=keep';
      const preview = 'https://image.test/preview';
      await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0,
        showGallery: false,
        sources: [
          MediaSource(
              url: original,
              thumbnail: hasPreview ? preview : original,
              previewUrl: hasPreview ? preview : original,
              deferOriginal: true)
        ],
        imageProviderFactory: (url, _) {
          requests.add(url);
          return _Image(url, pixels);
        },
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(requests, isNot(contains(original)));
      if (hasPreview) expect(requests, contains(preview));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(requests.where((url) => url == original), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      pixels.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
