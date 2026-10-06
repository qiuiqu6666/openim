import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

const _previewDirectory =
    String.fromEnvironment('GROUP_AVATAR_DIALOG_PREVIEW_DIR');
const _boundaryKey = ValueKey('group-avatar-dialog-preview');
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

class _ImageHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) =>
      name == HttpHeaders.contentTypeHeader ? 'image/png' : null;
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes);
  final List<int> bytes;
  @override
  final headers = _ImageHeaders();
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest extends Fake implements HttpClientRequest {
  _ImageRequest(this.reply);
  final Future<HttpClientResponse> reply;
  @override
  final headers = _ImageHeaders();
  @override
  Future<HttpClientResponse> close() => reply;
}

class _ImageClient extends Fake implements HttpClient {
  final reply = Completer<HttpClientResponse>();
  final requested = <Uri>[];
  @override
  set autoUncompress(bool value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    return _ImageRequest(reply.future);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _loadPreviewFonts() async {
  if (_previewDirectory.isEmpty) return;
  final chinese = File('C:/Windows/Fonts/msyh.ttc');
  if (await chinese.exists()) {
    await (FontLoader('GroupAvatarPreviewFont')
          ..addFont(chinese
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes))))
        .load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
        ..addFont(rootBundle
            .load('packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
      .load();
}

Future<void> _pumpImages(WidgetTester tester) async {
  // Decode and disk cache I/O run outside the fake clock. Keep waiting bounded.
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  await tester.pump();
}

Finder _avatar(String name) => find
    .byWidgetPredicate((widget) => widget is AvatarView && widget.text == name);

ExtendedImageState _imageState(WidgetTester tester) =>
    tester.state(find.byType(ExtendedImage)) as ExtendedImageState;

Finder _expectCircle(WidgetTester tester, String name) {
  final avatar = _avatar(name);
  expect(avatar, findsOneWidget);
  final circle = find.descendant(of: avatar, matching: find.byType(ClipOval));
  expect(circle, findsOneWidget);
  expect(find.descendant(of: avatar, matching: find.byType(ClipRRect)),
      findsNothing);
  expect(tester.renderObject(circle), isA<RenderClipOval>());
  expect(tester.getSize(circle), const Size(46, 46));
  return circle;
}

Future<void> _expectClippedCorners(
    WidgetTester tester, Iterable<Finder> circles) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      List<int> pixel(Offset point) {
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        return pixels!.buffer.asUint8List(offset, 4).toList();
      }

      for (final circle in circles) {
        final rect = tester.getRect(circle);
        // The square fallback is opaque blue. Its corner must instead expose
        // the same dialog surface as the neighbouring space outside the avatar.
        expect(pixel(rect.topLeft + const Offset(2, 2)),
            pixel(rect.topLeft + const Offset(-2, 2)));
      }
    } finally {
      image.dispose();
    }
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_previewDirectory.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final target = File('$_previewDirectory/$name.png');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late List<int> imageBytes;
  late String runID;
  setUpAll(() async {
    cache = await Directory.systemTemp.createTemp('group-avatar-dialog-test-');
    imageBytes =
        await File('openim_common/assets/images/share_app_logo_99chat.png')
            .readAsBytes();
    runID = '${DateTime.now().microsecondsSinceEpoch}';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (_) async => cache.path);
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    await cache.delete(recursive: true);
  });
  setUp(() => Get.testMode = true);
  tearDown(() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    Get.reset();
  });

  for (final dark in [false, true]) {
    for (final multiple in [false, true]) {
      testWidgets(
          '${multiple ? 'multiple' : 'single'} group recipients stay round '
          'through fallback/loading and confirmation dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final oldDark = Styles.isDark;
        Styles.isDark = dark;
        addTearDown(() => Styles.isDark = oldDark);
        await tester.runAsync(_loadPreviewFonts);
        final client = _ImageClient();
        debugNetworkImageHttpClientProvider = () => client;
        try {
          final groupURL = multiple
              ? 'https://avatars.example.test/$runID/group-$dark.png'
              : null;
          final recipients = <({String name, String? faceURL, bool isGroup})>[
            (name: '研发群', faceURL: groupURL, isGroup: true),
            (name: '项目群', faceURL: null, isGroup: true),
            (name: '小林', faceURL: null, isGroup: false),
          ];
          final dialog = ContactCardSendDialog(
              name: '秋秋',
              recipientName: multiple ? '研发群、项目群、小林' : '研发群',
              recipientFaceURL: groupURL,
              recipientIsGroup: true,
              recipients: multiple ? recipients : const []);
          bool? result;
          Future<void> open(BuildContext context) async {
            result = await showDialog<bool>(
                context: context, builder: (_) => dialog);
          }

          await tester.pumpWidget(ScreenUtilInit(
              designSize: const Size(375, 812),
              builder: (_, __) => RepaintBoundary(
                  key: _boundaryKey,
                  child: GetMaterialApp(
                      debugShowCheckedModeBanner: false,
                      translations: TranslationService(),
                      locale: const Locale('zh', 'CN'),
                      supportedLocales: const [Locale('zh', 'CN')],
                      localizationsDelegates: const [
                        GlobalMaterialLocalizations.delegate,
                        GlobalWidgetsLocalizations.delegate,
                        GlobalCupertinoLocalizations.delegate,
                      ],
                      theme: ThemeData(
                          brightness: dark ? Brightness.dark : Brightness.light,
                          colorScheme: ColorScheme.fromSeed(
                              seedColor: AppTokens.accent,
                              brightness:
                                  dark ? Brightness.dark : Brightness.light,
                              surface: AppTokens.surface(dark: dark)),
                          fontFamily: _previewDirectory.isEmpty
                              ? null
                              : 'GroupAvatarPreviewFont'),
                      home: Scaffold(
                          body: Builder(
                              builder: (context) => TextButton(
                                  onPressed: () => open(context),
                                  child: const Text('打开确认'))))))));
          await tester.tap(find.text('打开确认'));
          await tester.pump(const Duration(milliseconds: 400));
          await _pumpImages(tester);
          expect(
              tester.widget<ContactCardSendDialog>(
                  find.byType(ContactCardSendDialog)),
              same(dialog));
          final groups = multiple ? ['研发群', '项目群'] : ['研发群'];
          final circles =
              groups.map((name) => _expectCircle(tester, name)).toList();
          for (final name in groups) {
            expect(tester.widget<AvatarView>(_avatar(name)).isGroup, isTrue);
          }
          if (multiple) {
            _expectCircle(tester, '小林');
            expect(tester.widget<AvatarView>(_avatar('小林')).isGroup, isFalse);
            expect(client.requested.map((uri) => uri.toString()), [groupURL]);
            expect(
                _imageState(tester).extendedImageLoadState, LoadState.loading);
          }
          await _expectClippedCorners(tester, circles);
          final variant =
              '${multiple ? 'multiple' : 'single'}-${dark ? 'dark' : 'light'}';
          await _capture(
              tester, '$variant-${multiple ? 'loading' : 'fallback'}');
          if (multiple) {
            client.reply.complete(_ImageResponse(imageBytes));
            await _pumpImages(tester);
            expect(_imageState(tester).extendedImageLoadState,
                LoadState.completed);
            _expectCircle(tester, '研发群');
            expect(tester.widget<AvatarView>(_avatar('研发群')).url, groupURL);
            await _expectClippedCorners(tester, circles);
            await _capture(tester, '$variant-loaded');
          }
          await tester.tap(find.text(StrRes.cancel));
          await tester.pumpAndSettle();
          expect(result, isFalse);
          expect(find.byType(ContactCardSendDialog), findsNothing);
          await tester.tap(find.text('打开确认'));
          await tester.pump(const Duration(milliseconds: 400));
          await _pumpImages(tester);
          final reopened = tester.widget<ContactCardSendDialog>(
              find.byType(ContactCardSendDialog));
          expect(reopened, same(dialog));
          expect(reopened.recipients, multiple ? recipients : isEmpty);
          expect(reopened.recipientIsGroup, isTrue);
          expect(reopened.recipientFaceURL, groupURL);
          for (final name in groups) {
            _expectCircle(tester, name);
          }
          await tester.tap(find.text(StrRes.determine));
          await tester.pumpAndSettle();
          expect(result, isTrue);
          expect(find.byType(ContactCardSendDialog), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(tester.takeException(), isNull);
        } finally {
          // Flutter checks painting globals before the package tearDown runs.
          debugNetworkImageHttpClientProvider = null;
        }
      });
    }
  }
}
