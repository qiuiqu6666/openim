import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';
import '../../support/performance/render_test_fakes.dart';

class _PendingCompleter extends ImageStreamCompleter {}

class _PendingImage extends ViewerImageProvider {
  _PendingImage(super.url);
  bool cancelled = false;
  @override
  ImageStreamCompleter loadImage(
          ViewerImageProvider key, ImageDecoderCallback decode) =>
      _PendingCompleter();
  @override
  void cancel() {
    cancelled = true;
    super.cancel();
  }
}

void main() {
  testWidgets(
      'rapid traversal requests only current original and releases on exit',
      (tester) async {
    final requests = <_PendingImage>[];
    await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0,
        sources: List.generate(
            20,
            (i) => MediaSource(
                url: 'https://images.test/$i',
                thumbnail: 'https://images.test/$i')),
        imageProviderFactory: (url, _) {
          final image = _PendingImage(url);
          requests.add(image);
          return image;
        })));
    await tester.pump();
    expect(requests, hasLength(1));
    final page = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    for (var i = 1; i < 16; i++) {
      page.controller.jumpToPage(i);
      await tester.pump();
      await tester.pump();
      expect(requests.where((r) => !r.cancelled), hasLength(1));
    }
    expect(requests, hasLength(16));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(requests.every((r) => r.cancelled), isTrue);
    expect(tester.takeException(), isNull);
  });
}
