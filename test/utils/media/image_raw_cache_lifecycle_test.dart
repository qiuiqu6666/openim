import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  tearDown(() {
    rawImageDataMap.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('displaying 75 different images retains no global raw bytes',
      (tester) async {
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('image-raw-cache-')))!;
    final bytes = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(256, 256);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
    try {
      for (var batch = 0; batch < 3; batch++) {
        late BuildContext context;
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
          context = value;
          return const SizedBox.shrink();
        })));
        final images = <ExtendedImage>[];
        for (var i = 0; i < 25; i++) {
          final file = File('${directory.path}/$batch-$i.png');
          await tester.runAsync(() => file.writeAsBytes(bytes));
          final image = ImageUtil.fileImage(file: file, width: 16, height: 16)
              as ExtendedImage;
          images.add(image);
          await tester.runAsync(() => precacheImage(image.image, context));
        }
        await tester.pumpWidget(MaterialApp(home: Wrap(children: images)));
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.pump();
        expect(rawImageDataMap, isEmpty,
            reason: 'Batch ${batch + 1} must not accumulate compressed images');
        expect(PaintingBinding.instance.imageCache.currentSizeBytes, 0);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });

  test('network images opt out of raw storage while retaining disk cache', () {
    final image =
        ImageUtil.networkImage(url: 'https://media.example.test/avatar.png')
            as ExtendedImage;
    final provider = image.image as ExtendedNetworkImageProvider;
    expect(provider.cacheRawData, isFalse);
    expect(provider.cache, isTrue);

    final thumbnail = ImageUtil.networkImage(
      url: provider.url,
      cacheWidth: 144,
      cacheHeight: 144,
    ) as ExtendedImage;
    final resized = thumbnail.image as ExtendedResizeImage;
    expect(resized.cacheRawData, isFalse);
    expect((resized.imageProvider as ExtendedNetworkImageProvider).cacheRawData,
        isFalse);
  });

  testWidgets('explicit raw-data opt-in remains available to an editor',
      (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('image-editor-');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final source = await picture.toImage(64, 64);
      final bytes = (await source.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      source.dispose();
      picture.dispose();
      final file =
          await File('${directory.path}/source.png').writeAsBytes(bytes);
      try {
        final image = ImageUtil.fileImage(file: file, cacheRawData: true)
            as ExtendedImage;
        final provider = image.image as ExtendedFileImageProvider;
        final stream = provider.resolve(ImageConfiguration.empty);
        final decoded = Completer<void>();
        final listener = ImageStreamListener((info, _) {
          info.dispose();
          decoded.complete();
        }, onError: decoded.completeError);
        stream.addListener(listener);
        try {
          await decoded.future;
          expect(provider.rawImageData, orderedEquals(bytes));
          // A display-only request must not clear another owner's raw bytes;
          // editing and saving can still read the original.
          ImageUtil.fileImage(file: file);
          expect(provider.rawImageData, orderedEquals(bytes));
        } finally {
          stream.removeListener(listener);
        }
        await provider.evict();
        expect(rawImageDataMap, isEmpty);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
