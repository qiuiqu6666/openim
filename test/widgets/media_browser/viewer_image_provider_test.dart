import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';
import 'package:openim_common/src/utils/media/shared_image_disk_cache.dart';
import '../../support/performance/viewer_test_cache.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('encoded prefetch stores bytes without a codec and reuses disk cache',
      () async {
    final temp = await Directory.systemTemp.createTemp('encoded-prefetch-test');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      // Deliberately not an image: any attempted pixel decoding would fail.
      request.response.add([1, 2, 3]);
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/preview';
    final shared = SharedImageDiskCache(temporaryDirectory: () async => temp);
    ViewerImageProvider image() => ViewerImageProvider(url,
        cache: ViewerTestCache(),
        sharedCache: shared,
        createClient: () => _RealHttp().createHttpClient(null));
    try {
      final first = image();
      await first.prefetchEncoded();
      expect(await shared.read(url), [1, 2, 3]);
      expect(PaintingBinding.instance.imageCache.containsKey(first), isFalse);
      await image().prefetchEncoded();
      expect(requests, 1);
      final cancelled = image()..cancel();
      await expectLater(cancelled.prefetchEncoded(), throwsStateError);
    } finally {
      await server.close(force: true);
      await temp.delete(recursive: true);
    }
  });

  test('encoded cache-only miss never starts a download', () async {
    var clients = 0;
    final image = ViewerImageProvider('https://images.test/encoded-miss',
        cacheOnly: true, cache: ViewerTestCache(), createClient: () {
      clients++;
      return HttpClient();
    });
    await expectLater(image.prefetchEncoded(), throwsStateError);
    expect(clients, 0);
  });
  test('cache-only thumbnail miss never opens a network client', () async {
    var clients = 0;
    final image = ViewerImageProvider('https://images.test/cache-only-miss',
        cacheOnly: true, cache: ViewerTestCache(), createClient: () {
      clients++;
      return HttpClient();
    });
    final error = Completer<Object>();
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      info.dispose();
      fail('missing cache unexpectedly decoded');
    }, onError: (Object value, StackTrace? stack) => error.complete(value));
    stream.addListener(listener);
    expect(await error.future.timeout(const Duration(seconds: 5)),
        isA<StateError>());
    expect(clients, 0);
    stream.removeListener(listener);
    image.cancel();
  });
  test('cancels owned in-flight original and does not persist partial bytes',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    server.listen((request) {
      received.complete();
    });
    final image = ViewerImageProvider('http://127.0.0.1:${server.port}/pending',
        cache: ViewerTestCache(),
        createClient: () => _RealHttp().createHttpClient(null));
    final finished = Completer<Object>();
    final stream = image.resolve(ImageConfiguration.empty);
    final listener =
        ImageStreamListener((_, __) => fail('cancelled request decoded'),
            onError: (Object error, StackTrace? stack) {
      if (!finished.isCompleted) finished.complete(error);
    });
    stream.addListener(listener);
    await received.future.timeout(const Duration(seconds: 5));
    image.cancel();
    await finished.future.timeout(const Duration(seconds: 5));
    stream.removeListener(listener);
    expect(PaintingBinding.instance.imageCache.containsKey(image), isFalse);
    await server.close(force: true);
  });
  test('detached cancelled request finishes without a global image error',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    server.listen((request) => received.complete());
    final image = ViewerImageProvider(
        'http://127.0.0.1:${server.port}/detached',
        cache: ViewerTestCache(),
        createClient: () => _RealHttp().createHttpClient(null));
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      info.dispose();
      fail('cancelled request decoded');
    });
    stream.addListener(listener);
    await received.future.timeout(const Duration(seconds: 5));
    stream.removeListener(listener);
    image.cancel();
    // Give the aborted socket and codec futures time to deliver their errors.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(PaintingBinding.instance.imageCache.containsKey(image), isFalse);
  });

  test('decode budget preserves aspect ratio without upscaling', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bytes =
          await File('openim_common/assets/images/ic_archive_99chat.png')
              .readAsBytes();
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    final image = ViewerImageProvider('http://127.0.0.1:${server.port}/image',
        maxPixels: 1000000,
        cache: ViewerTestCache(),
        createClient: () => _RealHttp().createHttpClient(null));
    final done = Completer<void>();
    final chunks = <ImageChunkEvent>[];
    final completer = image.loadImage(image, (buffer, {getTargetSize}) async {
      final size = getTargetSize!(4000, 16000);
      expect(size.width, 500);
      expect(size.height, 2000);
      final small = getTargetSize(100, 200);
      expect(small.width, 100);
      expect(small.height, 200);
      return ui.instantiateImageCodecFromBuffer(buffer);
    });
    final listener = ImageStreamListener((info, _) {
      info.dispose();
      done.complete();
    },
        onChunk: chunks.add,
        onError: (Object error, StackTrace? stack) =>
            done.completeError(error, stack));
    completer.addListener(listener);
    await done.future.timeout(const Duration(seconds: 5));
    expect(chunks, isNotEmpty);
    expect(chunks.last.cumulativeBytesLoaded, chunks.last.expectedTotalBytes);
    completer.removeListener(listener);
    image.cancel();
    await server.close(force: true);
  });
}
