import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/gallery_image_precache.dart';

class _ControlledCompleter extends ImageStreamCompleter {
  void complete(ui.Image bitmap) => setImage(ImageInfo(image: bitmap.clone()));
}

class _ControlledImage extends ImageProvider<_ControlledImage> {
  _ControlledImage() {
    keepAlive = completer.keepAlive();
  }
  final _ControlledCompleter completer = _ControlledCompleter();
  late final ImageStreamCompleterHandle keepAlive;
  int starts = 0;

  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(ImageConfiguration configuration, ImageStream stream,
      _ControlledImage key, ImageErrorListener handleError) {
    starts++;
    stream.setCompleter(completer);
  }

  void complete(ui.Image bitmap) =>
      completer.complete(bitmap);
}

void main() {
  late ui.Image bitmap;
  final providers = <_ControlledImage>[];
  setUp(() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    bitmap = picture.toImageSync(1, 1);
    picture.dispose();
  });
  tearDown(() {
    for (final provider in providers) {
      provider.keepAlive.dispose();
    }
    providers.clear();
    bitmap.dispose();
  });
  _ControlledImage makeImage() {
    final provider = _ControlledImage();
    providers.add(provider);
    return provider;
  }

  Future<BuildContext> mount(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    return context;
  }

  testWidgets('completed warmup can navigate, invalidate and close repeatedly',
      (tester) async {
    final context = await mount(tester);
    final image = makeImage()..complete(bitmap);
    final helper = ImagePreviewGalleryPrecache();
    void warm() => helper.precacheAdjacent(
          context: context,
          centerIndex: 0,
          itemCount: 2,
          resolveProvider: (_) => image,
        );
    warm();
    await tester.pump();
    warm();
    await tester.pump();
    helper.invalidate();
    helper.invalidate();
    helper.dispose();
    helper.dispose();
    expect(tester.takeException(), isNull);
    expect(image.completer.hasListeners, isFalse);
  });

  testWidgets('rapid navigation keeps one real load and only the latest center',
      (tester) async {
    final context = await mount(tester);
    final images = List.generate(12, (_) => makeImage());
    final requested = <int>[];
    final helper = ImagePreviewGalleryPrecache();
    addTearDown(helper.dispose);
    void warm(int center) => helper.precacheAdjacent(
          context: context,
          centerIndex: center,
          itemCount: images.length,
          radius: 1,
          resolveProvider: (index) {
            requested.add(index);
            return images[index];
          },
        );
    warm(0);
    warm(3);
    warm(6);
    warm(9);
    await tester.pump(const Duration(seconds: 6));
    expect(requested, [1], reason: 'A timeout cannot free a real load slot');
    expect(images.where((image) => image.completer.hasListeners).length, 1);
    images[1].complete(bitmap);
    await tester.pump();
    expect(requested, [1, 10], reason: 'Intermediate centers must be dropped');
    images[10].complete(bitmap);
    await tester.pump();
    expect(requested, [1, 10, 8]);
    images[8].complete(bitmap);
    await tester.pump();
    expect(images.any((image) => image.completer.hasListeners), isFalse);
  });

  testWidgets(
      'invalidate retains active budget; disposal detaches before return',
      (tester) async {
    final context = await mount(tester);
    final active = makeImage();
    final next = makeImage();
    final helper = ImagePreviewGalleryPrecache();
    helper.precacheAdjacent(
      context: context,
      centerIndex: 0,
      itemCount: 2,
      resolveProvider: (_) => active,
    );
    helper.invalidate();
    helper.precacheAdjacent(
      context: context,
      centerIndex: 4,
      itemCount: 6,
      resolveProvider: (_) => next,
    );
    await tester.pump(const Duration(seconds: 8));
    expect(next.starts, 0);
    helper.dispose();
    expect(active.completer.hasListeners, isFalse);
    active.complete(bitmap);
    await tester.pump();
    expect(next.starts, 0,
        reason: 'Late frames after exit cannot restart work');
    helper.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a late image error after exit is best-effort and keeps no frames',
      (tester) async {
    final context = await mount(tester);
    final active = makeImage();
    final helper = ImagePreviewGalleryPrecache();
    helper.precacheAdjacent(
      context: context,
      centerIndex: 0,
      itemCount: 2,
      resolveProvider: (_) => active,
    );
    helper.dispose();
    expect(active.completer.hasListeners, isFalse);
    active.completer.reportError(exception: StateError('late failed image'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed or throwing provider does not block remaining work',
      (tester) async {
    final context = await mount(tester);
    final first = makeImage();
    final second = makeImage()..complete(bitmap);
    final helper = ImagePreviewGalleryPrecache();
    addTearDown(helper.dispose);
    helper.precacheAdjacent(
      context: context,
      centerIndex: 0,
      itemCount: 4,
      resolveProvider: (index) {
        if (index == 1) return first;
        if (index == 2) throw StateError('bad provider');
        return second;
      },
    );
    first.completer.reportError(exception: StateError('bad image'));
    await tester.pump();
    expect(first.completer.hasListeners, isFalse);
    expect(second.starts, 1);
    expect(tester.takeException(), isNull);
  });
}
