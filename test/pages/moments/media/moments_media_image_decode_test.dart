import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/media/moments_media_image.dart';
import 'package:openim/services/moments_repository.dart';

import '../../../support/performance/render_test_fakes.dart';
import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

Future<void> _decodeFrames(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('thumbnail decode is bounded while reporting original ratio',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    Size? dimensions;
    await tester.pumpWidget(renderTestHost(SizedBox.square(
        dimension: 80,
        child: MomentsMediaImage(
            repository: fixture.repository,
            media: momentsUiPhotos.first,
            onDimensions: (value) => dimensions = value))));
    await _decodeFrames(tester);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    final resized = image.image as ResizeImage;
    expect(resized.width, (80 * tester.view.devicePixelRatio).ceil());
    expect(resized.height, lessThanOrEqualTo(1080));
    expect(dimensions, const Size(576, 1024));
    final key = await resized.obtainKey(ImageConfiguration.empty);
    expect(
        PaintingBinding.instance.imageCache.statusForKey(key).tracked, isTrue);
    fixture.repository.resetSession();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(PaintingBinding.instance.imageCache.statusForKey(key).untracked,
        isTrue);
    expect(fixture.api.mediaRequests, ['preview-scenery:true']);
  });

  testWidgets('encoded dimensions from a replaced resource are never reported',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    final pending = Completer<Uint8List>();
    final oldBytes = fixture.api.mediaBytes['preview-scenery']!;
    fixture.api.mediaWork = (media, _) async => media.mediaId == 'old'
        ? pending.future
        : fixture.api.mediaBytes['preview-cover']!;
    final reported = <Size>[];
    Future<void> mount(MomentMedia media) =>
        tester.pumpWidget(renderTestHost(SizedBox.square(
            dimension: 80,
            child: MomentsMediaImage(
                repository: fixture.repository,
                media: media,
                onDimensions: reported.add))));
    await mount(const MomentMedia(mediaId: 'old'));
    await mount(const MomentMedia(mediaId: 'new'));
    await _decodeFrames(tester);
    final accepted = List<Size>.of(reported);
    expect(accepted, isNotEmpty);
    expect(accepted.single.width / accepted.single.height, closeTo(4 / 3, .01));
    pending.complete(oldBytes);
    await _decodeFrames(tester);
    expect(reported, accepted);
    expect(fixture.api.mediaRequests, ['old:true', 'new:true']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large phone image decodes at most 1080 without full-size raster',
      (tester) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const Color(0xFF3A5D74), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(4096, 2048);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
    final api = RenderTestApi()..mediaWork = (_, __) async => bytes!;
    final repository = renderTestRepository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(renderTestHost(SizedBox.square(
        dimension: 600,
        child: MomentsMediaImage(
            repository: repository,
            media: const MomentMedia(mediaId: 'large')))));
    await _decodeFrames(tester);
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.width, 1080);
    expect(resized.height, 540);
    await _decodeFrames(tester);
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image!.width, 1080);
    expect(raw.image!.height, 540);
    expect(tester.takeException(), isNull);
  });
}
