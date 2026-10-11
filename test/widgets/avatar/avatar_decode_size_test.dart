import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

Future<ui.Image> _decode(ImageProvider provider) async {
  final result = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener((info, _) {
    result.complete(info.image.clone());
    info.dispose();
  }, onError: result.completeError);
  stream.addListener(listener);
  try {
    return await result.future;
  } finally {
    stream.removeListener(listener);
  }
}

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final ratio in [1.0, 2.0, 3.0]) {
    testWidgets('avatar decodes at display size multiplied by DPR $ratio',
        (tester) async {
      final file = (await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp('avatar-size-');
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final original = await picture.toImage(256, 256);
        final bytes =
            (await original.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
        original.dispose();
        picture.dispose();
        return File('${directory.path}/avatar.png').writeAsBytes(bytes);
      }))!;
      try {
        // Let native decode finish in the real async zone before mounting the
        // widget; fake-async image I/O cannot make progress in pumpAndSettle.
        final size = (16 * ratio).toInt();
        final preload = ImageUtil.fileImage(
          file: file,
          cacheWidth: size,
          cacheHeight: size,
          resizePolicy: ResizeImagePolicy.fit,
        ) as ExtendedImage;
        (await tester.runAsync(() => _decode(preload.image)))!.dispose();
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(devicePixelRatio: ratio),
              child: Center(
                child: AvatarView(
                  width: 16,
                  height: 16,
                  url: 'https://media.example.test/avatar.png',
                  file: file,
                ),
              ),
            ),
          ),
        ));
        final image = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
        final resized = image.image as ExtendedResizeImage;
        expect(resized.width, size);
        expect(resized.height, size);
        expect(resized.policy, ResizeImagePolicy.fit);
        final decoded = (await tester.runAsync(() => _decode(resized)))!;
        expect(decoded.width, size);
        expect(decoded.height, size);
        decoded.dispose();
        expect(rawImageDataMap, isEmpty);

        final preview = ImageUtil.fileImage(file: file) as ExtendedImage;
        final original = (await tester.runAsync(() => _decode(preview.image)))!;
        expect(original.width, 256);
        expect(original.height, 256);
        original.dispose();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => file.parent.delete(recursive: true));
      }
    });
  }

  testWidgets('network avatars use the same decode bounds with raw data off',
      (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: 3),
          child: AvatarView(
            width: 54,
            height: 54,
            url: 'https://media.example.test/avatar.png',
            lowMemory: true,
          ),
        ),
      ),
    ));
    final image = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    final resized = image.image as ExtendedResizeImage;
    expect(resized.width, 162);
    expect(resized.height, 162);
    expect(resized.cacheRawData, isFalse);
    final provider = resized.imageProvider as ExtendedNetworkImageProvider;
    expect(provider.cacheRawData, isFalse);
    expect(provider.url, 'https://media.example.test/avatar.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
