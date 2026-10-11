import '../../support/performance/viewer_test_cache.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

import '../../support/performance/render_test_fakes.dart';

class _RealHttp extends HttpOverrides {}

Future<Uint8List> _png(Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 60), Paint()..color = Colors.orange);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<void> _settle(WidgetTester tester) async {
  // File availability and image decoding are separate asynchronous stages.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
  }
}

ExtendedImageGestureState _gesture(WidgetTester tester) => tester
    .state<ExtendedImageGestureState>(find.byType(ExtendedImageGesture).first);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final shape in {
    'exact screen': const Size(375, 812),
    'slightly taller': const Size(375, 850),
    'near screen': const Size(375, 900),
    'slightly shorter': const Size(375, 800),
    'retina screenshot': const Size(1179, 2556),
    'just below reading overflow': const Size(375, 974),
    'square': const Size(300, 300),
    'panorama': const Size(8000, 40),
    'one pixel': const Size(1, 1),
  }.entries) {
    for (final direction in [-1, 1]) {
      testWidgets(
          '${shape.key} swipes ${direction < 0 ? "up" : "down"} to close',
          (tester) async {
        _phone(tester);
        final bytes = (await tester.runAsync(() => _png(shape.value)))!;
        await tester.pumpWidget(renderTestHost(const Text('chat')));
        final nav = Navigator.of(tester.element(find.text('chat')));
        nav.push(MaterialPageRoute<void>(
            builder: (_) => MediaBrowser(
                  initialIndex: 0,
                  sources: [MediaSource(thumbnail: '', bytes: bytes)],
                )));
        await _settle(tester);
        await tester.timedDragFrom(Offset(180, direction < 0 ? 560 : 260),
            Offset(0, direction * 300.0), const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.byType(MediaBrowser), findsNothing);
        expect(find.text('chat'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
          variant: TargetPlatformVariant(
              {TargetPlatform.android, TargetPlatform.iOS}));
    }
  }

  for (final shape in {
    'square': const Size(300, 300),
    'portrait': const Size(300, 500),
    'landscape': const Size(600, 300),
    'panorama': const Size(2400, 100),
    'small': const Size(20, 20),
    'one pixel wide panorama': const Size(8192, 1),
    'large square': const Size(4096, 4096),
  }.entries) {
    testWidgets('${shape.key} stays fully visible and centered',
        (tester) async {
      _phone(tester);
      final bytes = (await tester.runAsync(() => _png(shape.value)))!;
      await tester.pumpWidget(renderTestHost(MediaBrowser(
          initialIndex: 0,
          sources: [MediaSource(thumbnail: '', bytes: bytes)])));
      await _settle(tester);
      final details = _gesture(tester).gestureDetails!;
      final rect = details.destinationRect!;
      expect(rect.width, lessThanOrEqualTo(375));
      expect(rect.height, lessThanOrEqualTo(812));
      expect(rect.center.dx, closeTo(375 / 2, 0.01));
      expect(rect.center.dy, closeTo(812 / 2, 0.01));
      expect(rect.width / rect.height,
          closeTo(shape.value.width / shape.value.height, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  for (final local in [false, true]) {
    testWidgets('${local ? 'file' : 'memory'} long image fits width from top',
        (tester) async {
      _phone(tester);
      final bytes = (await tester.runAsync(() => _png(const Size(120, 2400))))!;
      File? file;
      if (local) {
        file = await tester.runAsync(() async {
          final directory = await Directory.systemTemp.createTemp('media-fit-');
          return File('${directory.path}/long.png').writeAsBytes(bytes);
        });
        addTearDown(() async {
          // Only remove the fixture file and its now-empty temporary directory.
          await file!.delete();
          await file.parent.delete();
        });
      }
      await tester.pumpWidget(renderTestHost(MediaBrowser(
          initialIndex: 0,
          sources: [
            MediaSource(thumbnail: '', file: file, bytes: local ? null : bytes)
          ])));
      if (file != null) {
        await tester.runAsync(() => precacheImage(
            ExtendedFileImageProvider(file!),
            tester.element(find.byType(MediaBrowser))));
      }
      await _settle(tester);
      final rect = _gesture(tester).gestureDetails!.destinationRect!;
      expect(rect.width, closeTo(375, 0.01));
      expect(rect.height, closeTo(7500, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      expect(rect.left, closeTo(0, 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final legacy in [false, true]) {
    testWidgets(
        '${legacy ? 'legacy' : 'shared'} network original adapts to width',
        (tester) async {
      _phone(tester);
      final bytes = (await tester.runAsync(() => _png(const Size(120, 2400))))!;
      final thumbnail =
          (await tester.runAsync(() => _png(const Size(120, 120))))!;
      final server = (await tester
          .runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
      final client = (await tester
          .runAsync(() async => _RealHttp().createHttpClient(null)))!;
      final previousClient = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => client;
      await tester.runAsync(() async {
        server.listen((request) async {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response
              .add(request.uri.path == '/original.png' ? bytes : thumbnail);
          await request.response.close();
        });
      });
      addTearDown(() async {
        debugNetworkImageHttpClientProvider = previousClient;
        client.close(force: true);
        await server.close(force: true);
      });
      final url = 'http://127.0.0.1:${server.port}/original.png';
      final source = MediaSource(
          url: url, thumbnail: 'http://127.0.0.1:${server.port}/thumbnail.png');
      await tester.pumpWidget(renderTestHost(const SizedBox.shrink()));
      await tester.runAsync(() async {
        await precacheImage(ExtendedNetworkImageProvider(url),
            tester.element(find.byType(Scaffold)));
        await tester.pumpWidget(renderTestHost(legacy
            ? ChatPicturePreview(images: [source])
            : MediaBrowser(
                initialIndex: 0,
                sources: [source],
                imageProviderFactory: (url, pixels) => ViewerImageProvider(url,
                    maxPixels: pixels,
                    cache: ViewerTestCache(),
                    createClient: () => _RealHttp().createHttpClient(null)))));
        await precacheImage(
            tester
                .widget<AdaptiveMediaImage>(
                    find.byType(AdaptiveMediaImage).first)
                .image,
            tester.element(find.byType(AdaptiveMediaImage).first));
      });
      await _settle(tester);
      final rect = _gesture(tester).gestureDetails!.destinationRect!;
      expect(rect.width, closeTo(375, 0.01));
      expect(rect.height, closeTo(7500, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = previousClient;
    });
  }

  for (final viewport in [
    const Size(320, 568),
    const Size(812, 375),
    const Size(768, 1024)
  ]) {
    testWidgets('near viewport $viewport supports gallery swipe then dismissal',
        (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bytes = (await tester
          .runAsync(() => _png(Size(viewport.width, viewport.height * 1.1))))!;
      await tester.pumpWidget(
          renderTestHost(const Text('chat'), brightness: Brightness.dark));
      Navigator.of(tester.element(find.text('chat')))
          .push(MaterialPageRoute<void>(
              builder: (_) => MediaBrowser(
                    initialIndex: 0,
                    sources: [
                      MediaSource(thumbnail: '', bytes: bytes, tag: 'first'),
                      MediaSource(thumbnail: '', bytes: bytes, tag: 'second')
                    ],
                  )));
      await _settle(tester);
      await tester.timedDragFrom(
          Offset(viewport.width * .8, viewport.height / 2),
          Offset(-viewport.width * .7, 0),
          const Duration(milliseconds: 500));
      await _settle(tester);
      expect(find.text('2/2'), findsOneWidget);
      await tester.timedDragFrom(
          Offset(viewport.width / 2, viewport.height * .3),
          Offset(0, viewport.height * .4),
          const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('zoomed near-screen photo pans and closes after restoring fit',
      (tester) async {
    _phone(tester);
    final bytes = (await tester.runAsync(() => _png(const Size(375, 850))))!;
    await tester.pumpWidget(renderTestHost(const Text('chat')));
    Navigator.of(tester.element(find.text('chat')))
        .push(MaterialPageRoute<void>(
            builder: (_) => MediaBrowser(
                  initialIndex: 0,
                  sources: [MediaSource(thumbnail: '', bytes: bytes)],
                )));
    await _settle(tester);
    Future<void> doubleTap() async {
      await tester.tapAt(const Offset(180, 400));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(180, 400));
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(_gesture(tester).gestureDetails!.totalScale, closeTo(2, .01));
    await tester.timedDragFrom(const Offset(180, 500), const Offset(0, -250),
        const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsOneWidget);
    await doubleTap();
    expect(_gesture(tester).gestureDetails!.totalScale, closeTo(1, .01));
    // A short drag cancels cleanly and does not poison the next full swipe.
    await tester.timedDragFrom(const Offset(180, 350), const Offset(0, 45),
        const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsOneWidget);
    await tester.timedDragFrom(const Offset(180, 280), const Offset(0, 320),
        const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsNothing);
    expect(tester.takeException(), isNull);
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets(
      'extreme narrow image remains finite and readable with pinch and drag',
      (tester) async {
    _phone(tester);
    final bytes = (await tester.runAsync(() => _png(const Size(1, 8192))))!;
    await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0, sources: [MediaSource(thumbnail: '', bytes: bytes)])));
    await _settle(tester);
    var rect = _gesture(tester).gestureDetails!.destinationRect!;
    expect(rect.isFinite, isTrue);
    expect(rect.width, closeTo(375, .01));
    expect(rect.top, closeTo(0, .01));
    await tester.timedDragFrom(const Offset(180, 500), const Offset(0, -280),
        const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    rect = _gesture(tester).gestureDetails!.destinationRect!;
    expect(rect.top, lessThan(-200));
    final scale = _gesture(tester).gestureDetails!.totalScale!;
    final left = await tester.startGesture(const Offset(120, 400), pointer: 1);
    final right = await tester.startGesture(const Offset(250, 400), pointer: 2);
    await left.moveTo(const Offset(80, 400));
    await right.moveTo(const Offset(290, 400));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(_gesture(tester).gestureDetails!.totalScale!, greaterThan(scale));
    expect(_gesture(tester).gestureDetails!.destinationRect!.isFinite, isTrue);
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long image pans vertically and still swipes to the next photo',
      (tester) async {
    _phone(tester);
    final bytes = (await tester.runAsync(() => _png(const Size(120, 2400))))!;
    final pages = <int>[];
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: [
        MediaSource(thumbnail: '', bytes: bytes, tag: 'long'),
        MediaSource(thumbnail: '', bytes: renderTestPng(), tag: 'next'),
      ],
      onPageChanged: pages.add,
    )));
    await _settle(tester);
    await tester.timedDragFrom(const Offset(300, 500), const Offset(-180, -280),
        const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(
        _gesture(tester).gestureDetails!.destinationRect!.top, lessThan(-200));
    expect(pages, isEmpty);
    await tester.timedDragFrom(const Offset(300, 400), const Offset(-500, 0),
        const Duration(milliseconds: 400));
    await _settle(tester);
    expect(pages, contains(1));
    expect(find.text('2/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long image double tap zooms relative to reading width',
      (tester) async {
    _phone(tester);
    final bytes = (await tester.runAsync(() => _png(const Size(120, 2400))))!;
    await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0, sources: [MediaSource(thumbnail: '', bytes: bytes)])));
    await _settle(tester);
    Future<void> doubleTap() async {
      await tester.tapAt(const Offset(180, 350));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(180, 350));
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(_gesture(tester).gestureDetails!.destinationRect!.width,
        closeTo(750, 0.01));
    await tester.pump(const Duration(milliseconds: 400));
    await doubleTap();
    expect(_gesture(tester).gestureDetails!.destinationRect!.width,
        closeTo(375, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long image flick covers a screen and respects edges',
      (tester) async {
    _phone(tester);
    final bytes = (await tester.runAsync(() => _png(const Size(120, 2400))))!;
    await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0, sources: [MediaSource(thumbnail: '', bytes: bytes)])));
    await _settle(tester);

    Future<void> flick({bool down = false}) async {
      await tester.flingFrom(
          down ? const Offset(180, 280) : const Offset(180, 560),
          Offset(0, down ? 250 : -250),
          1800);
      await tester.pumpAndSettle();
    }

    await flick();
    var rect = _gesture(tester).gestureDetails!.destinationRect!;
    // A short flick should advance through a readable screen of a long image,
    // without changing its scale or dismissing the preview.
    expect(-rect.top, greaterThan(812));
    expect(-rect.top, lessThan(1624));
    expect(rect.width, closeTo(375, 0.01));
    await flick(down: true);
    expect(_gesture(tester).gestureDetails!.destinationRect!.top,
        closeTo(0, 0.01));

    for (var i = 0; i < 8; i++) {
      await flick();
    }
    rect = _gesture(tester).gestureDetails!.destinationRect!;
    expect(rect.bottom, closeTo(812, 0.01));
    expect(rect.width, closeTo(375, 0.01));
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(tester.takeException(), isNull);
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('long image slow drag stays precise and touching stops a flick',
      (tester) async {
    _phone(tester);
    final bytes = (await tester.runAsync(() => _png(const Size(120, 2400))))!;
    await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0, sources: [MediaSource(thumbnail: '', bytes: bytes)])));
    await _settle(tester);
    await tester.timedDragFrom(const Offset(180, 500), const Offset(0, -160),
        const Duration(milliseconds: 1000));
    final beforeRelease = _gesture(tester).gestureDetails!.destinationRect!.top;
    await tester.pumpAndSettle();
    var rect = _gesture(tester).gestureDetails!.destinationRect!;
    expect(-rect.top, inInclusiveRange(120, 180));
    expect(rect.top, closeTo(beforeRelease, 1));

    await tester.flingFrom(const Offset(180, 560), const Offset(0, -250), 1800);
    await tester.pump(const Duration(milliseconds: 50));
    final hold = await tester.startGesture(const Offset(180, 400));
    final stoppedAt = _gesture(tester).gestureDetails!.destinationRect!.top;
    await tester.pump(const Duration(milliseconds: 300));
    rect = _gesture(tester).gestureDetails!.destinationRect!;
    expect(rect.top, closeTo(stoppedAt, 0.01));
    expect(rect.width, closeTo(375, 0.01));
    await hold.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long image adapts to a resized viewport without losing its page',
      (tester) async {
    _phone(tester);
    final bytes = (await tester.runAsync(() => _png(const Size(120, 2400))))!;
    await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0, sources: [MediaSource(thumbnail: '', bytes: bytes)])));
    await _settle(tester);
    tester.view.physicalSize = const Size(812, 375);
    await tester.pumpAndSettle();
    final rect = _gesture(tester).gestureDetails!.destinationRect!;
    expect(rect.width, closeTo(812, 0.01));
    expect(rect.top, closeTo(0, 0.01));
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
