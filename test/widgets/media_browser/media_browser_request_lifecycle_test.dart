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
  testWidgets('idle warmup is bounded and chrome changes keep the pager intact',
      (tester) async {
    final requests = <_PendingImage>[];
    final budgets = <int>[];
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 3,
      sources: List.generate(
          8,
          (i) => MediaSource(
              url: 'https://images.test/$i',
              thumbnail: 'https://images.test/$i')),
      imageProviderFactory: (url, pixels) {
        budgets.add(pixels);
        final request = _PendingImage(url);
        requests.add(request);
        return request;
      },
    )));
    await tester.pump();
    final pager = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    expect(requests.length, inInclusiveRange(2, 3));
    await tester.pump(const Duration(milliseconds: 200));
    expect(requests.map((r) => r.url), [
      'https://images.test/3',
      'https://images.test/2',
      'https://images.test/4'
    ]);
    expect(budgets.last, lessThanOrEqualTo(2048 * 2048));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(
        identical(
            pager,
            tester.widget<ExtendedImageGesturePageView>(
                find.byType(ExtendedImageGesturePageView))),
        isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(requests, hasLength(3),
        reason: 'Only the two immediate neighbors are warmed');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(requests.every((r) => r.cancelled), isTrue);
  });

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
    expect(requests.length, inInclusiveRange(2, 3));
    final page = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    for (var i = 1; i < 16; i++) {
      page.controller.jumpToPage(i);
      await tester.pump();
      await tester.pump();
      expect(requests.where((r) => !r.cancelled).length, lessThanOrEqualTo(8));
    }
    expect(requests.where((r) => !r.cancelled).length, lessThanOrEqualTo(8));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(requests.every((r) => r.cancelled), isTrue);
    expect(tester.takeException(), isNull);
  });
}
