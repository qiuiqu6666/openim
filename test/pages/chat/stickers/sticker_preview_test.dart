import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_structured_message.dart';
import 'package:visibility_detector/visibility_detector.dart';

late Uint8List _imageFixture;
Uint8List _png() => _imageFixture;

class _ImageHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) =>
      name == HttpHeaders.contentTypeHeader ? 'image/png' : null;
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final headers = _ImageHeaders();
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _png().length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_png()).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest extends Fake implements HttpClientRequest {
  @override
  final headers = _ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => _ImageResponse();
}

class _ImageClient extends Fake implements HttpClient {
  @override
  set autoUncompress(bool value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest();
  @override
  void close({bool force = false}) {}
}

class _ImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _ImageClient();
}

Future<void> _mount(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      locale: const Locale('zh', 'CN'),
      translations: TranslationService(),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: child,
        bottomNavigationBar: const SizedBox(height: 60),
      ),
    ),
  ));
  await _settleImages(tester);
}

Future<void> _settleImages(WidgetTester tester) async {
  debugNetworkImageHttpClientProvider = () => _ImageClient();
  // Image decoders complete outside the fake clock; an active loading spinner
  // must not make route and control assertions depend on pumpAndSettle.
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 150));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pump(const Duration(milliseconds: 300));
  debugNetworkImageHttpClientProvider = null;
}

void _expectCloseOnly(WidgetTester tester) {
  final browser = find.byType(MediaBrowser);
  expect(browser, findsOneWidget);
  expect(tester.getRect(browser), const Rect.fromLTWH(0, 0, 375, 812));
  expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  expect(find.byType(IconButton), findsOneWidget);
  expect(find.byKey(const ValueKey('media-preview-info')), findsNothing);
  expect(find.byIcon(Icons.download), findsNothing);
  expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
  expect(find.byIcon(Icons.ios_share), findsNothing);
  expect(find.byIcon(Icons.more_horiz), findsNothing);
  expect(find.text('1/1'), findsNothing);
}

Message _sticker(String data, {required bool sent, bool legacy = false}) =>
    Message.fromJson({
      'clientMsgID': 'sticker-${sent ? 'sent' : 'received'}',
      'contentType': legacy ? MessageType.custom : MessageType.customFace,
      'sendID': sent ? 'me' : 'peer',
      'recvID': sent ? 'peer' : 'me',
      'senderNickname': sent ? 'Me' : 'Peer',
      'sessionType': ConversationType.single,
      'sendTime': 1700000000000,
      'isRead': true,
      'status': MessageStatus.succeeded,
      if (legacy) 'customElem': {'data': data},
      if (!legacy) 'faceElem': {'index': 0, 'data': data},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    _imageFixture = File('openim_common/assets/images/ic_archive_99chat.png')
        .readAsBytesSync();
    final cache = Directory('.dart_tool/sticker-preview-test-cache')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => cache.absolute.path);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
  });
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    HttpOverrides.global = _ImageHttpOverrides();
    debugNetworkImageHttpClientProvider = () => _ImageClient();
  });
  tearDown(() {
    HttpOverrides.global = null;
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    testWidgets('sticker preview covers navigation in $brightness',
        (tester) async {
      var closed = false;
      await _mount(tester, Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            await showStickerPreview(
                context,
                MediaSource(
                    thumbnail: '',
                    bytes: _png(),
                    senderName: 'Hidden sender',
                    sentAt: DateTime(2026, 10, 4),
                    onRetry: () => fail('Sticker preview must only show close'),
                    tag: 'sticker'));
            closed = true;
          },
          child: const Text('Preview sticker'),
        );
      }), brightness: brightness);

      await tester.tap(find.text('Preview sticker'));
      await _settleImages(tester);
      _expectCloseOnly(tester);
      expect(find.text('Hidden sender'), findsNothing);
      final image = find.byType(ExtendedImage);
      expect(image, findsOneWidget);
      expect((tester.state(image) as ExtendedImageState).extendedImageLoadState,
          LoadState.completed);
      await tester.tap(image);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.text('Preview sticker'), findsOneWidget);
      expect(closed, isTrue);

      closed = false;
      await tester.tap(find.text('Preview sticker'));
      await _settleImages(tester);
      _expectCloseOnly(tester);
      await tester.tap(image);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(image);
      await tester.pumpAndSettle();
      _expectCloseOnly(tester);
      expect(closed, isFalse,
          reason: 'Double taps belong to the image gesture, not dismissal.');
      await tester.longPress(image);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      _expectCloseOnly(tester);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.text('Preview sticker'), findsOneWidget);
      expect(closed, isTrue);

      closed = false;
      await tester.tap(find.text('Preview sticker'));
      await _settleImages(tester);
      _expectCloseOnly(tester);
      // The square fixture is centered; this coordinate lies on the empty
      // background below the toolbar and outside the image's painted bounds.
      await tester.tapAt(const Offset(24, 112));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.text('Preview sticker'), findsOneWidget);
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  const url = 'https://stickers.test/custom.gif';
  final formats = <String, String>{
    'raw URL': url,
    'URL JSON': jsonEncode({'url': url}),
    'nested URL JSON': jsonEncode({
      'data': {'url': url}
    }),
    'legacy custom emoji': jsonEncode({
      'customType': CustomMessageType.emoji,
      'data': {'url': url}
    }),
  };
  for (final sent in [false, true]) {
    for (final entry in formats.entries) {
      testWidgets(
          '${sent ? 'sent' : 'received'} ${entry.key} opens sticker preview',
          (tester) async {
        var delegatedTap = false;
        final message = _sticker(entry.value,
            sent: sent, legacy: entry.key == 'legacy custom emoji');
        await _mount(
            tester,
            ChatItemView(
                message: message,
                onTapUserProfile: (_) {},
                onClickItemView: () => delegatedTap = true));
        expect(find.byType(ChatStructuredMessage), findsOneWidget);
        await tester.tap(find.byType(ChatStructuredMessage));
        await _settleImages(tester);
        _expectCloseOnly(tester);
        expect(delegatedTap, isFalse,
            reason: 'The sticker preview must own its tap within the row.');
        final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
        expect(browser.sources.single.url, url);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(MediaBrowser), findsNothing);
        expect(find.byType(ChatStructuredMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('invalid sticker data never opens a media route', (tester) async {
    for (final invalid in ['', 'file:///private.png', '{"url":4}', 'https:']) {
      await _mount(tester,
          ChatStructuredMessage(message: _sticker(invalid, sent: true)));
      await tester.tap(find.byType(ChatStructuredMessage));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.text('[${StrRes.emoji}]'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final legacy in [false, true]) {
    testWidgets(
        'expired private ${legacy ? 'legacy emoji' : 'custom face'} cannot open preview',
        (tester) async {
      final data = legacy ? formats['legacy custom emoji']! : url;
      final message = Message.fromJson({
        ..._sticker(data, sent: false, legacy: legacy).toJson(),
        'attachedInfoElem': {
          'isPrivateChat': true,
          'hasReadTime': DateTime(2024, 1, 1).millisecondsSinceEpoch,
          'burnDuration': 1,
        },
      });
      expect(message.hasExpired, isTrue,
          reason: 'Use the SDK burn-after-reading metadata to expire content.');
      await _mount(tester, ChatStructuredMessage(message: message));
      expect(find.byType(ChatStructuredMessage), findsOneWidget);
      await tester.tap(find.byType(ChatStructuredMessage));
      await _settleImages(tester);
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
