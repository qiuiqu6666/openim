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
    'square': const Size(300, 300),
    'portrait': const Size(300, 500),
    'landscape': const Size(600, 300),
    'panorama': const Size(2400, 100),
    'small': const Size(20, 20),
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
            : MediaBrowser(initialIndex: 0, sources: [source])));
        await precacheImage(ExtendedNetworkImageProvider(url),
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
    await tester.timedDragFrom(const Offset(180, 500), const Offset(0, -280),
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
