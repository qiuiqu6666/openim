import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/media_recognition.dart';
import 'package:openim_common/src/widgets/media_browser/media_grid_thumbnail.dart';
import 'package:openim_common/src/widgets/media_browser/media_share_sheet.dart';

const _previewDirectory =
    String.fromEnvironment('MEDIA_BROWSER_ACTIONS_PREVIEW_DIR');
const _boundaryKey = ValueKey('media-actions-preview');
bool _fontsLoaded = false;

List<MediaSource> _pictures() {
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/q8AAAAASUVORK5CYII=');
  return [
    for (var index = 0; index < 2; index++)
      MediaSource(
        thumbnail: '',
        bytes: bytes,
        tag: 'message-$index',
        senderName: '秋秋',
        sentAt: DateTime(2026, 10, 5, 12, index),
      ),
  ];
}

class _NavigationLog extends NavigatorObserver {
  _NavigationLog(this.events);
  final List<String> events;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'media-preview') {
      events.add('pop:preview');
    } else if (route is PopupRoute) {
      events.add('pop:menu');
    }
    super.didPop(route, previousRoute);
  }
}

class _Fixture {
  final navigator = GlobalKey<NavigatorState>();
  final sources = ValueNotifier(_pictures());
  final events = <String>[];
  final callbacks = <String>[];
  late MaterialPageRoute<void> previewRoute;

  void _record(String action, int index) {
    callbacks.add('$action:$index');
    events.add('$action:$index');
  }

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    TargetPlatform platform = TargetPlatform.android,
    bool canViewInChat = true,
    bool canDelete = true,
    bool closeOnly = false,
    bool shareExtras = false,
    Size size = const Size(390, 844),
    double textScale = 1,
    Future<List<MediaShareRecipient>> Function()? recipientLoader,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    final oldDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    addTearDown(() => Styles.isDark = oldDark);
    await tester.runAsync(_loadPreviewFonts);
    await tester.pumpWidget(RepaintBoundary(
      key: _boundaryKey,
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigator,
          navigatorObservers: [_NavigationLog(events)],
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
            brightness: brightness,
            platform: platform,
            fontFamily: _fontsLoaded ? 'MediaActionsPreviewFont' : null,
            cupertinoOverrideTheme: CupertinoThemeData(
              brightness: brightness,
              primaryColor: CupertinoColors.systemBlue,
              barBackgroundColor:
                  AppTokens.surface(dark: brightness == Brightness.dark),
              applyThemeToAll: true,
              textTheme: const CupertinoTextThemeData().copyWith(
                actionTextStyle: TextStyle(
                  color: CupertinoColors.systemBlue,
                  fontSize: 17.sp,
                  fontFamily: _fontsLoaded ? 'MediaActionsPreviewFont' : null,
                  fontFamilyFallback:
                      _fontsLoaded ? const ['MediaActionsPreviewFont'] : null,
                ),
                textStyle: TextStyle(
                  color: CupertinoColors.label,
                  fontSize: 17.sp,
                  fontFamily: _fontsLoaded ? 'MediaActionsPreviewFont' : null,
                  fontFamilyFallback:
                      _fontsLoaded ? const ['MediaActionsPreviewFont'] : null,
                ),
              ),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: EasyLoading.init()(context, child),
          ),
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  previewRoute = MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'media-preview'),
                    builder: (_) => ValueListenableBuilder<List<MediaSource>>(
                      valueListenable: sources,
                      builder: (_, value, __) => MediaBrowser(
                        sources: value,
                        initialIndex: 0,
                        closeOnly: closeOnly,
                        onSave: (index) => _record('save', index),
                        onForward: (index) => _record('forward', index),
                        onFavorite: shareExtras
                            ? (index) => _record('favorite', index)
                            : null,
                        loadShareRecipients: recipientLoader ??
                            (shareExtras
                                ? () async => const [
                                      MediaShareRecipient(id: '1', name: '小林'),
                                      MediaShareRecipient(
                                          id: '2',
                                          name: '设计讨论群',
                                          isGroup: true),
                                      MediaShareRecipient(
                                          id: '3', name: 'Alex'),
                                      MediaShareRecipient(
                                          id: '4', name: '产品交流', isGroup: true),
                                      MediaShareRecipient(id: '5', name: '周末见'),
                                    ]
                                : null),
                        onForwardTo: shareExtras
                            ? (index, recipient) =>
                                _record('recipient:${recipient.id}', index)
                            : null,
                        onDelete: canDelete
                            ? (index) => _record('delete', index)
                            : null,
                        onViewInChat: canViewInChat
                            ? (index) => _record('locate', index)
                            : null,
                      ),
                    ),
                  );
                  navigator.currentState!.push(previewRoute);
                },
                child: const Text('原聊天页面'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('原聊天页面'));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      sources.dispose();
    });
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaShareSheet), findsOneWidget);
  }
}

Finder _action(String label) => find.byKey(ValueKey('media-share-$label'));

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(_action(label));
  await tester.pumpAndSettle();
  await tester.tap(_action(label));
  await tester.pumpAndSettle();
}

Future<void> _loadPreviewFonts() async {
  if (_previewDirectory.isEmpty || _fontsLoaded) return;
  final chinese = File('C:/Windows/Fonts/msyh.ttc');
  if (await chinese.exists()) {
    final bytes = ByteData.sublistView(await chinese.readAsBytes());
    // CupertinoActionSheet uses these system families directly. The test
    // engine needs explicit fonts; real devices supply native CJK fallback.
    for (final family in [
      'MediaActionsPreviewFont',
      'CupertinoSystemDisplay',
      'CupertinoSystemText',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    _fontsLoaded = true;
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_previewDirectory.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('$_previewDirectory/$name.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  tearDown(() => MediaImageRecognition.start = null);
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} recognized link opens only after menu closes',
        (tester) async {
      final fixture = _Fixture();
      var cancelled = false, opened = false;
      MediaImageRecognition.start = (_) => MediaRecognitionRequest(
          Future.value(MediaRecognitionResult([
            MediaRecognitionTarget(
              value: 'https://example.com',
              title: '二维码链接',
              copyLabel: '复制链接',
              openLabel: '识别图中二维码',
              open: (context, active) async {
                expect(active(), isTrue);
                expect(fixture.events, contains('pop:menu'));
                opened = true;
              },
            ),
          ])), () => cancelled = true);
      await fixture.mount(tester, brightness: brightness, shareExtras: true);
      await fixture.openMenu(tester);
      expect(find.text('https://example.com'), findsNothing);
      expect(tester.getTopLeft(_action('复制链接')).dy,
          tester.getTopLeft(_action('保存到相册')).dy);
      await _capture(tester, 'recognition-${brightness.name}');
      await tester.ensureVisible(find.text('识别图中二维码'));
      await tester.tap(find.text('识别图中二维码'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      expect(cancelled, isTrue);
      expect(find.byType(MediaBrowser), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('late recognition is discarded when menu closes', (tester) async {
    final fixture = _Fixture();
    final result = Completer<MediaRecognitionResult>();
    var cancelled = false;
    MediaImageRecognition.start = (_) =>
        MediaRecognitionRequest(result.future, () => cancelled = true);
    await fixture.mount(tester);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('正在识别二维码和地址…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_action('保存到相册'), findsOneWidget);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    result.complete(const MediaRecognitionResult([]));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(find.byType(MediaShareSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('recognized action cannot open for replaced source', (tester) async {
    final fixture = _Fixture();
    var opened = false;
    MediaImageRecognition.start = (_) => MediaRecognitionRequest(
        Future.value(MediaRecognitionResult([
          MediaRecognitionTarget(
              value: 'https://example.com', title: '二维码链接',
              copyLabel: '复制链接', openLabel: '打开链接',
              open: (context, active) async => opened = true),
        ])), () {});
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    fixture.sources.value = fixture.sources.value.reversed.toList();
    await tester.pump();
    await tester.ensureVisible(find.text('打开链接'));
    await tester.tap(find.text('打开链接'));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
  });
  testWidgets('recognized address copies the exact value', (tester) async {
    const address = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    MediaImageRecognition.start = (_) => MediaRecognitionRequest(
        Future.value(const MediaRecognitionResult([
          MediaRecognitionTarget(value: address,
              title: 'TRON 地址', copyLabel: '复制地址'),
        ])), () {});
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    await tester.ensureVisible(find.text('复制地址'));
    await tester.tap(find.text('复制地址'));
    await tester.pumpAndSettle();
    expect(copied, address);
    expect(find.byType(MediaBrowser), findsOneWidget);
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
  });
  testWidgets('recognition failure stays silent and reopening scans again',
      (tester) async {
    var attempt = 0;
    MediaImageRecognition.start = (_) => MediaRecognitionRequest(
        ++attempt == 1
            ? Future.error(StateError('unavailable'))
            : Future.value(const MediaRecognitionResult([])), () {});
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    expect(find.text('识别未完成，点击重试'), findsNothing);
    expect(_action('转发'), findsOneWidget);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await fixture.openMenu(tester);
    expect(find.text('识别未完成，点击重试'), findsNothing);
    expect(attempt, 2);
    expect(_action('转发'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('${brightness.name} ${platform.name} media uses shared sheet',
          (tester) async {
        final fixture = _Fixture();
        await fixture.mount(tester, brightness: brightness, platform: platform);
        await fixture.openMenu(tester);
        expect(find.byType(BottomSheet), findsOneWidget);
        for (final label in ['保存到相册', '转发', '在聊天中查看', '删除', '取消']) {
          expect(_action(label), findsOneWidget);
        }
        expect(
            Theme.of(tester.element(find.byType(MediaShareSheet))).brightness,
            brightness);
        final cancelRect = tester.getRect(_action('取消'));
        expect(cancelRect.bottom, lessThanOrEqualTo(844 - 34));
        await _capture(tester, '${brightness.name}-${platform.name}');
        await _choose(tester, '取消');
        expect(find.byType(MediaBrowser), findsOneWidget);
        expect(find.byType(MediaShareSheet), findsNothing);
        expect(fixture.callbacks, isEmpty);
        expect(fixture.events, ['pop:menu']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final selection in ['swipe', 'grid']) {
    testWidgets('$selection locates current item after menu and preview close',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      if (selection == 'grid') {
        await tester.tap(find.byTooltip('图片和视频'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(MediaGridThumbnail).at(0));
      } else {
        await tester.dragFrom(const Offset(320, 400), const Offset(-275, 0));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('2/2'), findsOneWidget);
      await fixture.openMenu(tester);
      await _choose(tester, '在聊天中查看');
      expect(fixture.events, ['pop:menu', 'pop:preview', 'locate:1']);
      expect(fixture.callbacks, ['locate:1']);
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.byType(MediaShareSheet), findsNothing);
      expect(find.text('原聊天页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final operation in [('保存到相册', 'save'), ('转发', 'forward')]) {
    testWidgets('${operation.$2} closes only the menu', (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.openMenu(tester);
      await _choose(tester, operation.$1);
      expect(fixture.events, ['pop:menu', '${operation.$2}:0']);
      expect(find.byType(MediaBrowser), findsOneWidget);
      expect(find.byType(MediaShareSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('delete closes menu and preview before notifying caller',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    await _choose(tester, '删除');
    expect(fixture.events, ['pop:menu', 'pop:preview', 'delete:0']);
    expect(find.byType(MediaBrowser), findsNothing);
    expect(find.text('原聊天页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without locate callback the menu offers no view-in-chat action',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, canViewInChat: false);
    await fixture.openMenu(tester);
    expect(_action('在聊天中查看'), findsNothing);
    await _choose(tester, '取消');
    expect(fixture.callbacks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locate alone still exposes the more menu', (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, canDelete: false);
    await fixture.openMenu(tester);
    expect(_action('删除'), findsNothing);
    await _choose(tester, '在聊天中查看');
    expect(fixture.events, ['pop:menu', 'pop:preview', 'locate:0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close-only preview exposes no actions even with all callbacks',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, closeOnly: true);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(find.byTooltip('图片和视频'), findsNothing);
    expect(find.byIcon(Icons.download), findsNothing);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    await tester.longPressAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    expect(find.byType(MediaShareSheet), findsNothing);
    expect(fixture.callbacks, isEmpty);
    await tester.tapAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsNothing);
    expect(fixture.callbacks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final label in ['保存到相册', '转发', '在聊天中查看', '删除']) {
    testWidgets('$label cannot apply a stale menu to a replacement source',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.openMenu(tester);
      fixture.sources.value = fixture.sources.value.reversed.toList();
      await tester.pump();
      await _choose(tester, label);
      expect(fixture.callbacks, isEmpty);
      expect(fixture.events, ['pop:menu']);
      expect(find.byType(MediaBrowser), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a rebuilt list retaining the same source keeps its valid choice',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    fixture.sources.value = List.of(fixture.sources.value);
    await tester.pump();
    await _choose(tester, '在聊天中查看');
    expect(fixture.events, ['pop:menu', 'pop:preview', 'locate:0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection after preview removal cannot call a disposed owner',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    fixture.navigator.currentState!.removeRoute(fixture.previewRoute);
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsNothing);
    expect(find.byType(MediaShareSheet), findsOneWidget);
    await _choose(tester, '在聊天中查看');
    expect(fixture.callbacks, isEmpty);
    expect(find.text('原聊天页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a newly pushed route cannot be popped by a pending menu choice',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    final locate = tester.widget<TextButton>(_action('在聊天中查看'));

    // Both operations happen before the sheet's awaiting caller resumes.
    locate.onPressed!();
    fixture.navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('新页面'))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('新页面'), findsOneWidget);
    expect(find.byType(MediaShareSheet), findsNothing);
    expect(find.byType(MediaBrowser), findsNothing);
    expect(find.byType(MediaBrowser, skipOffstage: false), findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    expect(fixture.events, ['pop:menu']);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} recipient panel and favorite',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, shareExtras: true, brightness: brightness);
      await fixture.openMenu(tester);
      expect(find.text('小林'), findsOneWidget);
      expect(find.text('收藏'), findsOneWidget);
      await _capture(tester, 'share-${brightness.name}');
      await _choose(tester, '小林');
      expect(fixture.callbacks, ['recipient:1:0']);
      expect(find.byType(MediaBrowser), findsOneWidget);
      await fixture.openMenu(tester);
      await _choose(tester, '收藏');
      expect(fixture.callbacks.last, 'favorite:0');
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('large text panel fits $size and keeps cancel reachable',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, shareExtras: true, size: size, textScale: 2);
      await fixture.openMenu(tester);
      expect(
          tester.getRect(_action('取消')).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await _choose(tester, '取消');
      expect(fixture.callbacks, isEmpty);
    });
  }

  testWidgets('gallery action opens gallery without closing preview',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.openMenu(tester);
    await _choose(tester, '图片和视频');
    expect(find.byType(MediaGridThumbnail), findsNWidgets(2));
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'recipient load failure can retry and empty list keeps forwarding',
      (tester) async {
    var attempts = 0;
    final fixture = _Fixture();
    await fixture.mount(tester, shareExtras: true, recipientLoader: () async {
      if (attempts++ == 0) throw StateError('offline');
      return [];
    });
    await fixture.openMenu(tester);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无最近会话'), findsOneWidget);
    await _choose(tester, '转发');
    expect(fixture.callbacks, ['forward:0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel shows only six recipients with two action rows',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester,
        shareExtras: true,
        recipientLoader: () async => [
              for (var i = 1; i <= 9; i++)
                MediaShareRecipient(id: '$i', name: '会话$i'),
            ]);
    await fixture.openMenu(tester);
    expect(_action('会话6'), findsOneWidget);
    expect(_action('会话7'), findsNothing);
    expect(_action('更多'), findsOneWidget);
    expect(tester.getTopLeft(_action('保存到相册')).dy,
        greaterThan(tester.getBottomLeft(_action('转发')).dy));
    await _capture(tester, 'six-recipients');
    await _choose(tester, '会话6');
    expect(fixture.callbacks, ['recipient:6:0']);
    await fixture.openMenu(tester);
    await _choose(tester, '更多');
    expect(fixture.callbacks, ['recipient:6:0', 'forward:0']);
    expect(find.byType(MediaShareSheet), findsNothing);
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press opens panel and stale recipient cannot forward',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, shareExtras: true);
    await tester.longPressAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    expect(find.byType(MediaShareSheet), findsOneWidget);
    fixture.sources.value = fixture.sources.value.reversed.toList();
    await tester.pump();
    await _choose(tester, '小林');
    expect(fixture.callbacks, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
