import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/picture/chat_picture_quality.dart';

Future<ui.Image> _decode(ImageProvider provider) {
  final result = Completer<ui.Image>();
  final stream = provider.resolve(const ImageConfiguration());
  late ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    result.complete(info.image.clone());
  }, onError: (Object error, StackTrace? stack) {
    stream.removeListener(listener);
    result.completeError(error, stack);
  });
  stream.addListener(listener);
  return result.future;
}

Future<File> _photo(Directory directory, String name, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawPaint(Paint()..color = Colors.white);
  for (var x = 0.0; x < size.width; x += 12) {
    canvas.drawRect(
        Rect.fromLTWH(x, 0, 6, size.height), Paint()..color = Colors.black);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return File('${directory.path}/$name.png')
      .writeAsBytes(data!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File longPhoto;
  late File normalPhoto;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('chat-picture-quality-');
    longPhoto = await _photo(directory, 'long', const Size(600, 7200));
    normalPhoto = await _photo(directory, 'normal', const Size(800, 400));
  });
  tearDownAll(() async {
    PaintingBinding.instance.imageCache.clear();
    await longPhoto.delete();
    await normalPhoto.delete();
    await directory.delete();
  });

  test('extreme image decode remains within the pixel and side budgets', () {
    for (final source in [
      const Size(1000, 100000),
      const Size(100000, 1000),
      const Size(40000, 40000),
    ]) {
      final size = ChatPictureQuality.decodeSize(
          source: source, displayWidth: 240, devicePixelRatio: 4);
      expect(size.width * size.height,
          lessThanOrEqualTo(ChatPictureQuality.maxDecodedPixels));
      expect(size.longestSide,
          lessThanOrEqualTo(ChatPictureQuality.maxDecodedSide));
      expect(size.shortestSide, greaterThanOrEqualTo(1));
    }
  });

  test('sufficient big picture avoids downloading the original', () {
    final picture = PictureElem(
      sourcePicture: PictureInfo(url: 'original'),
      bigPicture: PictureInfo(url: 'big', width: 480, height: 5760),
      snapshotPicture: PictureInfo(url: 'snapshot', width: 80, height: 960),
    );
    expect(ChatPictureQuality.croppedSource(picture, const Size(240, 2880)),
        'big');
    picture.bigPicture = PictureInfo(url: 'big', width: 160, height: 1920);
    expect(ChatPictureQuality.croppedSource(picture, const Size(240, 2880)),
        'original');
  });

  test('original signed URL is preserved and missing sources fall back', () {
    const signed = 'https://media.test/image.png?token=a%2Bb&expires=42';
    final picture = PictureElem(
      sourcePicture: PictureInfo(url: signed),
      snapshotPicture: PictureInfo(url: 'snapshot'),
    );
    expect(ChatPictureQuality.croppedSource(picture, const Size(240, 2880)),
        signed);
    picture.sourcePicture!.url = ' ';
    expect(ChatPictureQuality.croppedSource(picture, const Size(240, 2880)),
        'snapshot');
  });

  test('missing original dimensions use available image metadata', () {
    expect(
        ChatPictureQuality.sourceSize(PictureElem(
            sourcePicture: PictureInfo(width: 0, height: 0),
            bigPicture: PictureInfo(width: 400, height: 4800))),
        const Size(400, 4800));
  });

  for (final dpr in [1.0, 2.0, 3.0]) {
    testWidgets('long bubble preserves short-axis detail at ${dpr}x density',
        (tester) async {
      tester.view.physicalSize = Size(375 * dpr, 812 * dpr);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final message = Message()
        ..clientMsgID = 'long'
        ..pictureElem = PictureElem(
            sourcePath: longPhoto.path,
            sourcePicture: PictureInfo(width: 600, height: 7200));
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) {
              ScreenUtil.init(context, designSize: const Size(375, 812));
              return child!;
            },
            home: Scaffold(
                body: Center(
                    child: ChatPictureView(message: message, isISend: true)))));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      });
      final widget = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
      final decoded = (await tester.runAsync(() => _decode(widget.image)))!;
      final displayed = tester.getSize(find.byType(ChatPictureView));
      expect(displayed, const Size(120, 200));
      expect(decoded.width, (120 * dpr).toInt());
      expect(decoded.height, (1440 * dpr).toInt());

      // The old square decode discarded 11/12 of the horizontal detail.
      final old = ImageUtil.fileImage(
          file: longPhoto,
          width: 120,
          height: 120,
          cacheWidth: (120 * dpr).toInt(),
          cacheHeight: (120 * dpr).toInt(),
          resizePolicy: ResizeImagePolicy.fit) as ExtendedImage;
      final blurred = (await tester.runAsync(() => _decode(old.image)))!;
      expect(decoded.width, greaterThanOrEqualTo(blurred.width * 11));
      decoded.dispose();
      blurred.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary photo remains proportionate with a small decode',
      (tester) async {
    final size = ChatPictureQuality.decodeSize(
        source: const Size(800, 400), displayWidth: 120, devicePixelRatio: 2);
    final image = ImageUtil.fileImage(
        file: normalPhoto,
        width: 120,
        height: 60,
        cacheWidth: size.width.toInt(),
        cacheHeight: size.height.toInt(),
        resizePolicy: ResizeImagePolicy.fit) as ExtendedImage;
    final decoded = (await tester.runAsync(() => _decode(image.image)))!;
    expect(decoded.width, 240);
    expect(decoded.height, 120);
    decoded.dispose();
  });
}
