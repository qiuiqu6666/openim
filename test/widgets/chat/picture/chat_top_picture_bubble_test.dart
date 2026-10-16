import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_picture_gallery.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/quote/chat_quote_thumbnail.dart';

class _RealHttp extends HttpOverrides {}

class _FailedImage implements ExtendedImageState {
  @override
  LoadState get extendedImageLoadState => LoadState.failed;
  @override
  ImageProvider get imageProvider => const AssetImage('unused');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ui.Image> _decode(ImageProvider provider) {
  final result = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    result.complete(info.image.clone());
    info.dispose();
    stream.removeListener(listener);
  }, onError: (Object error, StackTrace? stack) {
    stream.removeListener(listener);
    result.completeError(error, stack);
  });
  stream.addListener(listener);
  return result.future.timeout(const Duration(seconds: 5));
}

Message _message(String base) => Message(
      clientMsgID: 'long-picture',
      contentType: MessageType.picture,
      ex: ChatPicturePreviewMetadata.withTopCrop(null,
          sourceURL: '$base/original.png', previewURL: '$base/top.png'),
      pictureElem: PictureElem(
        sourcePath: 'missing-local-original.png',
        sourcePicture:
            PictureInfo(url: '$base/original.png', width: 600, height: 7200),
        bigPicture:
            PictureInfo(url: '$base/original.png', width: 600, height: 7200),
        snapshotPicture:
            PictureInfo(url: '$base/top.png', width: 480, height: 864),
      ),
    );

Widget _page(Widget child) => MaterialApp(
      builder: (context, child) {
        ScreenUtil.init(context, designSize: const Size(375, 812));
        return child!;
      },
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final selfSent in [false, true]) {
    testWidgets('top preview decodes only visible pixels, self=$selfSent',
        (tester) async {
      tester.view.physicalSize = const Size(1125, 2436);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => HttpOverrides.runWithHttpOverrides(() async {
            final directory =
                await Directory.systemTemp.createTemp('top-bubble-');
            const channel = MethodChannel('plugins.flutter.io/path_provider');
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, (_) async => directory.path);
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawColor(Colors.red, BlendMode.src);
            final picture = recorder.endRecording();
            final image = await picture.toImage(480, 864);
            final png =
                (await image.toByteData(format: ui.ImageByteFormat.png))!
                    .buffer
                    .asUint8List();
            image.dispose();
            picture.dispose();
            final server =
                await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
            final requests = <String>[];
            server.listen((request) async {
              requests.add(request.uri.toString());
              request.response.add(png);
              await request.response.close();
            });
            try {
              final message = _message('http://127.0.0.1:${server.port}');
              await tester.pumpWidget(
                  _page(ChatPictureView(message: message, isISend: selfSent)));
              final widget =
                  tester.widget<ExtendedImage>(find.byType(ExtendedImage));
              final decoded = await _decode(widget.image);
              expect(decoded.width, 270);
              expect(decoded.height, 486);
              decoded.dispose();
              expect(tester.getSize(find.byType(ChatPictureView)),
                  const Size(90, 162));
              expect(requests, ['/top.png']);

              // Opening the full viewer still uses the complete attachment.
              final gallery =
                  await ChatPictureGallery.fromMessages([message], message);
              expect(gallery.sources.single.url,
                  message.pictureElem!.sourcePicture!.url);

              await tester
                  .pumpWidget(_page(ChatQuoteThumbnail(message: message)));
              final quote =
                  tester.widget<ExtendedImage>(find.byType(ExtendedImage));
              final quoted = await _decode(quote.image);
              expect(quoted.width, 120);
              expect(quoted.height, 216);
              quoted.dispose();
              expect(requests, ['/top.png']);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              await server.close(force: true);
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(channel, null);
              await directory.delete(recursive: true);
            }
          }, _RealHttp()));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed crop falls back to a complete image with its own bounds',
      (tester) async {
    tester.view.physicalSize = const Size(1125, 2436);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final message = _message('https://media.test');
    await tester
        .pumpWidget(_page(ChatPictureView(message: message, isISend: false)));
    final widget = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    final preview = widget.image as ExtendedResizeImage;
    expect(preview.width, 270);
    expect(preview.height, 486);
    final failed = widget.loadStateChanged!(_FailedImage()) as GestureDetector;
    final fallback =
        (failed.child! as ExtendedImage).image as ExtendedResizeImage;
    expect((fallback.imageProvider as ExtendedNetworkImageProvider).url,
        'https://media.test/original.png?height=640&width=640&type=image');
    expect(fallback.width, 270);
    expect(fallback.height, 3240);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
