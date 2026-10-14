import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('image condition');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Consumer {
  _Consumer(this.provider) {
    stream = provider.resolve(ImageConfiguration.empty);
    listener = ImageStreamListener((image, _) {
      frames++;
      image.dispose();
    }, onError: (Object error, StackTrace? stack) => errors.add(error));
  }
  final ImageProvider provider;
  late final ImageStream stream;
  late final ImageStreamListener listener;
  int frames = 0;
  final errors = <Object>[];
  bool attached = false;
  void attach() {
    attached = true;
    stream.addListener(listener);
  }

  void detach() {
    if (!attached) return;
    attached = false;
    stream.removeListener(listener);
  }
}

class _Server {
  _Server(this.server, this.directory, this.png);
  final HttpServer server;
  final Directory directory;
  final List<int> png;
  final requests = <HttpRequest>[];
  final consumers = <_Consumer>[];

  ImageProvider provider(String path, {int size = 16}) =>
      (ImageUtil.networkImage(
        url: 'http://127.0.0.1:${server.port}/$path.png',
        cacheWidth: size,
        cacheHeight: size,
      ) as ExtendedImage)
          .image;

  _Consumer consume(String path, {int size = 16, bool attach = true}) {
    final consumer = _Consumer(provider(path, size: size));
    consumers.add(consumer);
    if (attach) consumer.attach();
    return consumer;
  }

  Future<void> complete(HttpRequest request) async {
    try {
      request.response.add(png);
      await request.response.close();
    } catch (_) {
      // Tests deliberately abort consumers on the other end of this socket.
    }
  }

  Future<int> diskFiles() async {
    final cache = Directory('${directory.path}/cacheimage');
    return await cache.exists() ? (await cache.list().toList()).length : 0;
  }

  Future<void> close() async {
    for (final consumer in consumers) {
      consumer.detach();
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    for (final consumer in consumers) {
      await consumer.provider.evict();
    }
    await server.close(force: true);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await directory.delete(recursive: true);
  }
}

Future<void> _withServer(Future<void> Function(_Server) body) async {
  await HttpOverrides.runWithHttpOverrides(() async {
    final directory = await Directory.systemTemp.createTemp('managed-images-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff336699), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 32);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
    final server = _Server(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0), directory, png);
    server.server.listen((request) {
      server.requests.add(request);
      unawaited(request.response.done.then<void>((_) {}, onError: (_) {}));
    });
    try {
      await body(server);
    } finally {
      await server.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }, _RealHttp());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pending cache listener alone does not start a request', () async {
    await _withServer((server) async {
      final consumer = server.consume('not-yet-listened', attach: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(server.requests, isEmpty);
      consumer.attach();
      await _until(() => server.requests.length == 1);
      await server.complete(server.requests.single);
      await _until(() => consumer.frames == 1);
      expect(consumer.errors, isEmpty);
    });
  });

  test(
      'four active loads; queued cancellation starts no request and frees a slot',
      () async {
    await _withServer((server) async {
      final consumers = List.generate(8, (i) => server.consume('image-$i'));
      await _until(() => server.requests.length == 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(server.requests.length, 4);
      consumers[7].detach();
      consumers[0].detach();
      await _until(() => server.requests.length == 5);
      expect(server.requests.any((r) => r.uri.path == '/image-7.png'), isFalse);
      expect(consumers.expand((c) => c.errors), isEmpty);
      expect(await server.diskFiles(), 0);
    });
  });

  test('same decode key shares a request and surviving consumers keep it alive',
      () async {
    await _withServer((server) async {
      final first = server.consume('shared');
      final second = server.consume('shared');
      expect(first.stream.completer, same(second.stream.completer));
      await _until(() => server.requests.length == 1);
      first.detach();
      second.detach();
      first.attach(); // Same-frame transfer must not cancel the common task.
      await server.complete(server.requests.single);
      await _until(() => first.frames == 1);
      expect(second.frames, 0);
      expect(first.errors, isEmpty);
      expect(server.requests.length, 1);
      first.detach();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final cached = server.consume('shared');
      await _until(() => cached.frames > 0);
      expect(server.requests.length, 1);
      expect(await server.diskFiles(), 1);
    });
  });

  test('different decode keys do not cancel each other even for the same URL',
      () async {
    await _withServer((server) async {
      final small = server.consume('different-size', size: 8);
      final large = server.consume('different-size', size: 24);
      await _until(() => server.requests.length == 2);
      small.detach();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final request in server.requests) {
        await server.complete(request);
      }
      await _until(() => large.frames == 1);
      expect(small.frames, 0);
      expect(large.errors, isEmpty);
    });
  });

  test(
      'detaching a stalled response body cancels work and re-entry loads normally',
      () async {
    await _withServer((server) async {
      final consumer = server.consume('body-stalled');
      await _until(() => server.requests.length == 1);
      final response = server.requests.single.response;
      response.contentLength = server.png.length;
      response.add(server.png.take(8).toList());
      await response.flush();
      consumer.detach();
      await _until(
          () => PaintingBinding.instance.imageCache.pendingImageCount == 0);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
          consumer.errors, isEmpty); // Cancellation must not mount fallbacks.
      expect(consumer.frames, 0);
      expect(await server.diskFiles(), 0);
      final reentered = server.consume('body-stalled');
      await _until(() => server.requests.length == 2);
      await server.complete(server.requests.last);
      await _until(() => reentered.frames == 1);
      expect(reentered.errors, isEmpty);
    });
  });

  test('TickerMode style keep-alive can reattach the same cancelled stream',
      () async {
    await _withServer((server) async {
      final consumer = server.consume('pause-resume');
      final handle = consumer.stream.completer!.keepAlive();
      try {
        await _until(() => server.requests.length == 1);
        consumer.detach();
        await _until(
            () => PaintingBinding.instance.imageCache.pendingImageCount == 0);
        consumer.attach();
        await _until(() => server.requests.length == 2);
        await server.complete(server.requests.last);
        await _until(() => consumer.frames == 1);
        expect(consumer.errors, isEmpty);
      } finally {
        handle.dispose();
      }
    });
  });

  test('an older kept-alive stream cannot evict a newer task with the same key',
      () async {
    await _withServer((server) async {
      final old = server.consume('interleaved');
      final handle = old.stream.completer!.keepAlive();
      try {
        await _until(() => server.requests.length == 1);
        old.detach();
        await _until(
            () => PaintingBinding.instance.imageCache.pendingImageCount == 0);
        final current = server.consume('interleaved');
        await _until(() => server.requests.length == 2);
        old.attach();
        await _until(() => server.requests.length == 3);
        old.detach();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final joined = server.consume('interleaved');
        expect(joined.stream.completer, same(current.stream.completer));
        expect(server.requests.length, 3);
        await server.complete(server.requests[1]);
        await _until(() => current.frames == 1 && joined.frames == 1);
        expect(current.errors, isEmpty);
      } finally {
        handle.dispose();
      }
    });
  });
}
