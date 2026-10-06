import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/widgets/chat_video_thumbnail.dart';
import 'package:openim_common/openim_common.dart' show Config;

import '../../../../support/media/deferred_thumbnail_http.dart';

final _photoPath = File('assets/ai/11.webp').absolute.path;

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _mount(WidgetTester tester, ChatVideoThumbnail thumbnail) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SizedBox.square(dimension: 40, child: thumbnail)),
  ));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await _frames(tester);
}

Widget _plain(BuildContext _) => const Text('ordinary');
Widget _photo(BuildContext _, Widget image) =>
    Stack(children: [image, const Text('decoded')]);

void _thumbnailTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      DeferredThumbnailHttpClient.restore();
    }
  });
}

void main() {
  _thumbnailTest('history thumbnails load loopback objects through the IM API',
      (tester) async {
    final client = DeferredThumbnailHttpClient()..install();
    const objectPath = '/object/sangong/test/history.png';
    await _mount(
        tester,
        ChatVideoThumbnail(
          path: null,
          url: 'http://127.0.0.1:10002$objectPath',
          width: 40,
          fallbackBuilder: _plain,
        ));
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final network = provider is ResizeImage ? provider.imageProvider : provider;
    expect((network as NetworkImage).url, '${Config.imApiUrl}$objectPath');
    expect(client.requests, 1);
    client.bytes
        .complete(await tester.runAsync(() => File(_photoPath).readAsBytes()));
    await _frames(tester);
    expect(tester.takeException(), isNull);
  });

  _thumbnailTest('local success decorates only an actually decoded thumbnail',
      (tester) async {
    await _mount(
        tester,
        ChatVideoThumbnail(
          path: _photoPath,
          url: null,
          width: 40,
          fallbackBuilder: _plain,
          imageBuilder: _photo,
        ));
    expect(find.text('decoded'), findsOneWidget);
    expect(find.text('ordinary'), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  _thumbnailTest(
      'a pending remote image keeps the ordinary fallback until a frame decodes',
      (tester) async {
    final client = DeferredThumbnailHttpClient()..install();
    await _mount(
        tester,
        ChatVideoThumbnail(
          path: null,
          url: 'https://thumbnail.test/pending.webp',
          width: 40,
          fallbackBuilder: _plain,
          imageBuilder: _photo,
        ));
    expect(client.requests, 1);
    expect(find.text('ordinary'), findsOneWidget);
    expect(find.text('decoded'), findsNothing);
    client.bytes
        .complete(await tester.runAsync(() => File(_photoPath).readAsBytes()));
    await _frames(tester);
    expect(find.text('decoded'), findsOneWidget);
    expect(find.text('ordinary'), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
  });

  _thumbnailTest(
      'missing local and failed remote thumbnails keep the ordinary fallback',
      (tester) async {
    final client = DeferredThumbnailHttpClient()..install();
    await _mount(
        tester,
        ChatVideoThumbnail(
          path: '/missing/thumbnail.webp',
          url: 'https://thumbnail.test/failure.webp',
          width: 40,
          fallbackBuilder: _plain,
          imageBuilder: _photo,
        ));
    expect(client.requests, 1);
    client.bytes.completeError(StateError('image unavailable'));
    await _frames(tester);
    expect(find.text('ordinary'), findsOneWidget);
    expect(find.text('decoded'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _thumbnailTest('empty local and remote paths use the caller fallback',
      (tester) async {
    await _mount(
        tester,
        const ChatVideoThumbnail(
          path: null,
          url: null,
          width: 40,
          fallbackBuilder: _plain,
          imageBuilder: _photo,
        ));
    expect(find.text('ordinary'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _thumbnailTest(
      'old thumbnail callers retain the original image frame behavior',
      (tester) async {
    await _mount(
        tester, ChatVideoThumbnail(path: _photoPath, url: null, width: 40));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.frameBuilder, isNull,
        reason:
            'Existing video thumbnails must not gain a new loading transition');
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
