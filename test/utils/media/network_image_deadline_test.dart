import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('gzip images decode and a raw cache miss downloads only once', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final temp = await Directory.systemTemp.createTemp('image-gzip-cache-');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => temp.path);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2),
          ui.Paint()..color = const ui.Color(0xff336699));
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        final compressed = gzip.encode(png);
        request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        request.response.contentLength = compressed.length;
        request.response.add(compressed);
        await request.response.close();
      });
      final provider = ExtendedNetworkImageProvider(
          'http://127.0.0.1:${server.port}/gzip.png',
          cache: true,
          cacheKey: 'gzip',
          printError: false,
          retries: 0,
          timeLimit: const Duration(seconds: 1));
      final chunks = StreamController<ImageChunkEvent>();
      final events = chunks.stream.toList();
      try {
        expect(await provider.getNetworkImageData(chunkEvents: chunks), png);
        expect((await events).last.expectedTotalBytes, isNull);
        expect(await provider.getNetworkImageData(), png);
        expect(requests, 1);
      } finally {
        await server.close(force: true);
        await temp.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }, _RealHttp());
  });
  test('a corrupt disk image is replaced after one successful download',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final temp = await Directory.systemTemp.createTemp('image-cache-repair-');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => temp.path);
      final cached = File('${temp.path}/cacheimage/repaired');
      await cached.parent.create();
      await cached.writeAsString('broken');
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2),
          ui.Paint()..color = const ui.Color(0xff336699));
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        request.response.add(png);
        await request.response.close();
      });
      final provider = ExtendedNetworkImageProvider(
          'http://127.0.0.1:${server.port}/image.png',
          cache: true,
          cacheKey: 'repaired',
          printError: false,
          retries: 0,
          timeLimit: const Duration(seconds: 1));
      Future<void> load() async {
        final done = Completer<void>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener((image, sync) {
          image.dispose();
          done.complete();
        }, onError: (error, stack) => done.completeError(error, stack));
        stream.addListener(listener);
        try {
          await done.future.timeout(const Duration(seconds: 3));
        } finally {
          stream.removeListener(listener);
          await provider.evict();
        }
      }

      try {
        await load();
        expect(await cached.readAsBytes(), png);
        await load();
        expect(requests, 1);
      } finally {
        await server.close(force: true);
        await temp.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }, _RealHttp());
  });
  for (final bodyStalls in [false, true]) {
    test(
        'image fails within a deadline when ${bodyStalls ? 'body' : 'headers'} stalls',
        () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          if (bodyStalls) {
            request.response.contentLength = 5000;
            request.response.add([137, 80, 78, 71]);
            await request.response.flush();
          }
          // Deliberately hold the connection open, as a stalled mobile route does.
        });
        final failure = Completer<Object>();
        final provider = ExtendedNetworkImageProvider(
            'http://127.0.0.1:${server.port}/stalled.png',
            cache: false,
            retries: 0,
            printError: false,
            timeLimit: const Duration(milliseconds: 100));
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener((image, synchronous) {
          failure.completeError(StateError('unexpected image'));
        }, onError: (Object error, StackTrace? stack) {
          failure.complete(error);
        });
        stream.addListener(listener);
        try {
          expect(await failure.future.timeout(const Duration(seconds: 3)),
              isA<StateError>());
        } finally {
          stream.removeListener(listener);
          await provider.evict();
          await server.close(force: true);
        }
      }, _RealHttp());
    });
  }
}
