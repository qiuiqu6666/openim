import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/media_browser/media_grid_thumbnail.dart';

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
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
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
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
  }
}

Finder _action(String label) =>
    find.widgetWithText(CupertinoActionSheetAction, label);

Future<void> _choose(WidgetTester tester, String label) async {
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
        final sheet = tester
            .widget<CupertinoActionSheet>(find.byType(CupertinoActionSheet));
        expect(sheet.title, isNull);
        expect(sheet.actions, hasLength(4));
        expect(sheet.cancelButton, isNotNull);
        expect(find.byType(BottomSheet), findsNothing);
        for (final label in ['保存到相册', '转发', '在聊天中查看', '删除', '取消']) {
          expect(_action(label), findsOneWidget);
        }
        final delete = tester.widget<CupertinoActionSheetAction>(_action('删除'));
        expect(delete.isDestructiveAction, isTrue);
        expect(
            DefaultTextStyle.of(tester.element(find.text('保存到相册'))).style.color,
            CupertinoColors.systemBlue
                .resolveFrom(tester.element(find.text('保存到相册'))));
        expect(
            DefaultTextStyle.of(tester.element(find.text('删除'))).style.color,
            CupertinoColors.destructiveRed
                .resolveFrom(tester.element(find.text('删除'))));
        expect(
            CupertinoTheme.brightnessOf(
                tester.element(find.byType(CupertinoActionSheet))),
            brightness);
        final cancelRect = tester.getRect(_action('取消'));
        expect(cancelRect.bottom, lessThanOrEqualTo(844 - 34));
        await _capture(tester, '${brightness.name}-${platform.name}');
        await _choose(tester, '取消');
        expect(find.byType(MediaBrowser), findsOneWidget);
        expect(find.byType(CupertinoActionSheet), findsNothing);
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
        await tester.tap(find.byType(MediaGridThumbnail).at(1));
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
      expect(find.byType(CupertinoActionSheet), findsNothing);
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
      expect(find.byType(CupertinoActionSheet), findsNothing);
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
    expect(
        tester
            .widget<CupertinoActionSheet>(find.byType(CupertinoActionSheet))
            .actions,
        hasLength(3));
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
    expect(find.byType(CupertinoActionSheet), findsNothing);
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
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
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
    final locate = tester.widget<CupertinoActionSheetAction>(_action('在聊天中查看'));

    // Both operations happen before the sheet's awaiting caller resumes.
    locate.onPressed();
    fixture.navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('新页面'))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('新页面'), findsOneWidget);
    expect(find.byType(CupertinoActionSheet), findsNothing);
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
}
