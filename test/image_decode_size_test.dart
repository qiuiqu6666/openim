import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/image_util.dart';

Future<ui.Image> resolveImage(ImageProvider provider) async {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(const ImageConfiguration());
  late ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    completer.complete(info.image.clone());
  }, onError: (Object error, StackTrace? stack) {
    stream.removeListener(listener);
    completer.completeError(error, stack);
  });
  stream.addListener(listener);
  return completer.future;
}

void main() {
  test('decode dimensions account for display density and invalid sizes', () {
    expect(ImageUtil.decodeDimension(80.2, 3), 241);
    expect(ImageUtil.decodeDimension(80, 2), 160);
    expect(ImageUtil.decodeDimension(80, 0), 80);
    expect(ImageUtil.decodeDimension(0, 2), isNull);
    expect(ImageUtil.decodeDimension(double.infinity, 2), isNull);
  });

  testWidgets('bubble decode keeps aspect ratio and preview keeps the original',
      (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('image-decode-');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawPaint(Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final original = await picture.toImage(800, 400);
      final bytes = await original.toByteData(format: ui.ImageByteFormat.png);
      original.dispose();
      picture.dispose();
      final file = await File('${directory.path}/photo.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      try {
        final bubble = ImageUtil.fileImage(
          file: file,
          width: 80,
          height: 80,
          cacheWidth: ImageUtil.decodeDimension(80, 2),
          cacheHeight: ImageUtil.decodeDimension(80, 2),
          resizePolicy: ResizeImagePolicy.fit,
          cacheRawData: false,
        ) as ExtendedImage;
        final decodedBubble = await resolveImage(bubble.image);
        expect(decodedBubble.width, 160);
        expect(decodedBubble.height, 80);
        decodedBubble.dispose();

        final preview = ImageUtil.fileImage(file: file) as ExtendedImage;
        final decodedPreview = await resolveImage(preview.image);
        expect(decodedPreview.width, 800);
        expect(decodedPreview.height, 400);
        decodedPreview.dispose();
      } finally {
        PaintingBinding.instance.imageCache.clear();
        await directory.delete(recursive: true);
      }
    });
  });
}
