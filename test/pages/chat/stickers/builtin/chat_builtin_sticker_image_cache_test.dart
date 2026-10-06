import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker_image_cache.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker_sender.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_structured_message.dart';

import '../../../../support/media/deferred_thumbnail_http.dart';

final _sticker = ChatBuiltinStickerCatalog.stickers.first;
const _screen = Size(375, 812);
const _bubbleSize = Size.square(144);
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

ExtendedNetworkImageProvider _key(String url) =>
    ExtendedNetworkImageProvider(url, cache: true);

Message _roundTrip(Message message) => Message.fromJson(
    jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>);

class _Fixture {
  _Fixture(this.directory, this.url) {
    sender = ChatBuiltinStickerSender(
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      sessionKey: () => ('self', 'test-token'),
      cacheDirectory: () async => directory,
      upload: ({required id, required filePath, required fileName}) async {
        uploadPath = filePath;
        expect(fileName, _sticker.fileName);
        uploadedBytes = await File(filePath).readAsBytes();
        return {'url': url};
      },
      createFace: (data) async {
        // The actual default warm-up must finish before the SDK message exists.
        expect(
            PaintingBinding.instance.imageCache.containsKey(_key(url)), isTrue);
        return Message(
          clientMsgID: 'builtin-first-frame',
          sendID: 'self',
          recvID: 'peer',
          sessionType: ConversationType.single,
          contentType: MessageType.customFace,
          status: MessageStatus.sending,
          isRead: false,
          sendTime: 1700000000000,
          faceElem: FaceElem(index: -1, data: data),
        );
      },
      sendMessage: (message) async => sent.add(message),
      // Keep the production rootBundle and image warm-up, rather than replacing
      // either with a test image provider or a no-op cache hook.
    );
  }

  final Directory directory;
  final String url;
  late final ChatBuiltinStickerSender sender;
  final sent = <Message>[];
  late String uploadPath;
  late Uint8List uploadedBytes;

  Message get outgoing => _roundTrip(sent.single);

  void expectTemporaryFileRemoved() {
    expect(File(uploadPath).existsSync(), isFalse);
    expect(directory.listSync(), isEmpty);
  }
}

Future<_Fixture> _fixture(WidgetTester tester, String url) async {
  final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('openim-builtin-image-cache-')))!;
  final fixture = _Fixture(directory, url);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      _pathChannel, (_) async => directory.absolute.path);
  addTearDown(() async {
    fixture.sender.close();
    messenger.setMockMethodCallHandler(_pathChannel, null);
    final expectedPrefix =
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}'
        'openim-builtin-image-cache-';
    if (!directory.absolute.path.startsWith(expectedPrefix)) {
      throw StateError('Unexpected test directory: ${directory.absolute.path}');
    }
    await tester.runAsync(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  });
  return fixture;
}

Future<Uint8List> _assetBytes() async {
  final data = await rootBundle.load(_sticker.assetPath);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<void> _mount(WidgetTester tester, Message message,
    {Brightness brightness = Brightness.light,
    Key bubbleKey = const ValueKey('builtin-bubble')}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: _screen,
    builder: (_, __) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ChatStructuredMessage(key: bubbleKey, message: message),
        ),
      ),
    ),
  ));
  // Deliberately do not settle, precache, or pump an extra frame here. A newly
  // serialized outgoing bubble must render its PNG on the very first pump.
}

ui.Image _expectReadyImage(WidgetTester tester) {
  expect(find.byType(ChatStructuredMessage), findsOneWidget);
  expect(find.byType(ChatImageSticker), findsOneWidget);
  expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
  final raw = tester.widget<RawImage>(find.byType(RawImage));
  expect(raw.image, isNotNull);
  expect(raw.image!.width, _sticker.width);
  expect(raw.image!.height, _sticker.height);
  expect(tester.getSize(find.byType(ChatImageSticker)), _bubbleSize);
  expect(tester.takeException(), isNull);
  return raw.image!;
}

void _expectUncached(String url) {
  final status = PaintingBinding.instance.imageCache.statusForKey(_key(url));
  expect(status.pending, isFalse);
  expect(status.keepAlive, isFalse);
  expect(status.live, isFalse);
}

DeferredThumbnailHttpClient _deferredHttp() {
  final http = DeferredThumbnailHttpClient()..install();
  addTearDown(() {
    // Even a failed first-frame assertion must not leave an unresolved request.
    if (!http.bytes.isCompleted) http.bytes.complete(<int>[]);
  });
  return http;
}

void _testWidgets(
    String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      // The binding checks debug globals before package tearDown executes.
      DeferredThumbnailHttpClient.restore();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final brightness in Brightness.values) {
    _testWidgets(
        'real bundled sender renders the first frame and receipt without a '
        'network placeholder in $brightness', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final http = _deferredHttp();
      final url =
          'https://stickers.test/builtin-first-${brightness.name}.png?signature=fresh';
      final fixture = await _fixture(tester, url);
      await tester.runAsync(() => fixture.sender.send(_sticker));

      expect(fixture.sent, hasLength(1));
      final actualBytes = await tester.runAsync(_assetBytes);
      expect(fixture.uploadedBytes, orderedEquals(actualBytes!));
      final outgoing = fixture.outgoing;
      final payload = StickerImageData.tryParse(outgoing.faceElem!.data)!;
      expect(outgoing.contentType, MessageType.customFace);
      expect(outgoing.faceElem!.index, -1);
      expect(outgoing.status, MessageStatus.sending);
      expect(payload.url, url);
      expect(Uri.parse(payload.url).scheme, 'https');
      expect(payload.width, _sticker.width);
      expect(payload.height, _sticker.height);
      expect(outgoing.faceElem!.data, isNot(contains(_sticker.assetPath)));
      expect(outgoing.faceElem!.data, isNot(contains(fixture.uploadPath)));
      fixture.expectTemporaryFileRemoved();

      await _mount(tester, outgoing, brightness: brightness);
      final firstImage = _expectReadyImage(tester).clone();
      addTearDown(firstImage.dispose);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, _key(url));
      expect(
          PaintingBinding.instance.imageCache
              .containsKey(ExtendedNetworkImageProvider(url, cache: false)),
          isFalse);
      expect(http.requests, 0);

      final receipt = _roundTrip(outgoing)
        ..status = MessageStatus.succeeded
        ..serverMsgID = 'server-builtin-ack'
        ..seq = 15
        ..isRead = true;
      await _mount(tester, _roundTrip(receipt), brightness: brightness);
      expect(_expectReadyImage(tester).isCloneOf(firstImage), isTrue);
      expect(ChatStructuredMessage.emojiUrl(receipt), url);
      expect(http.requests, 0);

      // A list-row replacement, not merely a retained StatefulWidget, must
      // also consume the same standard URL cache without flashing a fallback.
      await _mount(tester, _roundTrip(receipt),
          brightness: brightness,
          bubbleKey: const ValueKey('replacement-builtin-bubble'));
      expect(_expectReadyImage(tester).isCloneOf(firstImage), isTrue);
      expect(http.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    _testWidgets(
        'evicting the ordinary image cache restores remote loading in '
        '$brightness', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final http = _deferredHttp();
      final url = 'https://stickers.test/builtin-evict-${brightness.name}.png';
      final fixture = await _fixture(tester, url);
      await tester.runAsync(() => fixture.sender.send(_sticker));
      fixture.expectTemporaryFileRemoved();
      final message = fixture.outgoing;
      await _mount(tester, message, brightness: brightness);
      _expectReadyImage(tester);
      expect(http.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      _expectUncached(url);

      await _mount(tester, _roundTrip(message), brightness: brightness);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
      expect(tester.getSize(find.byType(ChatImageSticker)), _bubbleSize);
      expect(
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .every((image) => image.image == null),
          isTrue);
      final placeholder = find.byIcon(Icons.emoji_emotions_outlined);
      expect(tester.widget<Icon>(placeholder).color,
          Theme.of(tester.element(placeholder)).colorScheme.onSurfaceVariant);

      for (var attempt = 0; attempt < 100 && http.requests == 0; attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(http.requests, 1);
      http.bytes.complete(fixture.uploadedBytes);
      for (var frame = 0; frame < 25; frame++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byIcon(Icons.emoji_emotions_outlined).evaluate().isEmpty) {
          break;
        }
      }
      _expectReadyImage(tester);
      expect(http.requests, 1);
      expect(ChatStructuredMessage.emojiUrl(message), url);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  _testWidgets(
      'an existing URL cache keeps its image without decoding new bytes',
      (tester) async {
    const url = 'https://stickers.test/builtin-retained.png';
    await tester.runAsync(() async {
      await warmBuiltinStickerImage(url: url, bytes: await _assetBytes());
    });
    final cache = PaintingBinding.instance.imageCache;
    final original = cache.putIfAbsent(
        _key(url), () => throw StateError('Expected the warmed URL cache'));
    expect(original, isNotNull);
    await tester.runAsync(() => warmBuiltinStickerImage(
        url: url, bytes: Uint8List.fromList([0, 1, 2])));
    expect(
        cache.putIfAbsent(
            _key(url), () => throw StateError('Existing URL was lost')),
        same(original));
    expect(tester.takeException(), isNull);
  });

  _testWidgets('invalid PNG errors leave no pending or live image cache entry',
      (tester) async {
    const url = 'https://stickers.test/builtin-invalid.png';
    Object? failure;
    await tester.runAsync(() async {
      try {
        await warmBuiltinStickerImage(
            url: url, bytes: Uint8List.fromList([0, 1, 2]));
      } catch (error) {
        failure = error;
      }
    });
    expect(failure, isNotNull);
    _expectUncached(url);
    expect(tester.takeException(), isNull);
  });

  _testWidgets(
      'a stale owner before decoding does not seed or decode bad bytes',
      (tester) async {
    const url = 'https://stickers.test/builtin-already-stale.png';
    var checks = 0;
    await tester.runAsync(() => warmBuiltinStickerImage(
          url: url,
          bytes: Uint8List.fromList([0, 1, 2]),
          isCurrent: () {
            checks++;
            return false;
          },
        ));
    expect(checks, 1);
    _expectUncached(url);
    expect(tester.takeException(), isNull);
  });

  _testWidgets('an owner that changes during decoding leaves no image entry',
      (tester) async {
    const url = 'https://stickers.test/builtin-stale-after-decode.png';
    var checks = 0;
    await tester.runAsync(() async {
      await warmBuiltinStickerImage(
        url: url,
        bytes: await _assetBytes(),
        isCurrent: () => ++checks == 1,
      );
    });
    expect(checks, 2);
    _expectUncached(url);
    expect(tester.takeException(), isNull);
  });
}
