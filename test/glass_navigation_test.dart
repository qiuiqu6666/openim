import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/home/glass_bottom_nav_bar.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

String get _previewDirectory {
  final configured = Platform.environment['HOME_GLASS_PREVIEW'] ??
      const String.fromEnvironment('HOME_GLASS_PREVIEW');
  if (configured.isNotEmpty) return configured;
  return const bool.fromEnvironment('GLASS_PREVIEW') ? '/tmp' : '';
}

Widget _badgedIcon(IconData icon, int count) => SizedBox(
      width: 32,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(icon),
          Positioned(top: -2, right: -2, child: UnreadCountView(count: count)),
        ],
      ),
    );

Finder _bottomSurface() => find.descendant(
      of: find.byType(GlassBottomNavBar),
      matching: find.byType(LiquidGlassSurface),
    );

bool _hasLiquidBottom() => find
    .descendant(
        of: _bottomSurface(), matching: find.byType(glass.GlassContainer))
    .evaluate()
    .isNotEmpty;

Future<void> _exportNavigation(WidgetTester tester, String name) async {
  if (_previewDirectory.isEmpty) return;
  final renderer = _hasLiquidBottom() ? 'liquid' : 'fallback';
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')));
  await tester.runAsync(() async {
    final directory = Directory(_previewDirectory);
    await directory.create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${directory.path}/$name-$renderer.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  debugPrint('HOME_GLASS_PREVIEW: $name renderer=$renderer');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    final fontDirectory = Platform.environment['GLASS_PREVIEW_FONTS'] ??
        const String.fromEnvironment('GLASS_PREVIEW_FONTS');
    if (fontDirectory.isNotEmpty) {
      for (final entry in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf'
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(File('$fontDirectory/${entry.value}')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      }
    }
    if (_previewDirectory.isNotEmpty) {
      final chinese = File('C:/Windows/Fonts/msyh.ttc');
      if (await chinese.exists()) {
        await (FontLoader('HomeGlassCjk')
              ..addFont(chinese.readAsBytes().then(ByteData.sublistView)))
            .load();
      }
      if (fontDirectory.isEmpty) {
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      }
    }
  });
  setUp(() async {
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.automatic);
  });
  Future<void> pumpNavigation(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    TargetPlatform platform = TargetPlatform.iOS,
    Size size = const Size(375, 812),
    bool highContrast = false,
    double scale = 1,
    bool reducedMotion = false,
    ValueChanged<int>? onSelected,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeData(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['HomeGlassCjk'],
        platform: platform,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF), brightness: brightness),
        brightness: brightness);
    var selectedIndex = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.only(top: 44, bottom: 34),
              highContrast: highContrast,
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion),
          child: RepaintBoundary(
            key: const ValueKey('preview'),
            child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                      extendBody: true,
                      extendBodyBehindAppBar: true,
                      appBar: GlassAppBar(title: const Text('消息'), actions: [
                        IconButton(
                            onPressed: () {}, icon: const Icon(Icons.add))
                      ]),
                      body: ListView.builder(
                        padding: EdgeInsets.only(
                            top: 44 + NavigationGlassTokens.toolbarHeight),
                        itemCount: 16,
                        itemBuilder: (_, index) => ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text('联系人 ${index + 1}'),
                          subtitle: const Text('最近收到的消息'),
                        ),
                      ),
                      bottomNavigationBar: GlassBottomNavBar(
                          config: NavBarConfig(
                        selectedIndex: selectedIndex,
                        onItemSelected: (index) {
                          setState(() => selectedIndex = index);
                          onSelected?.call(index);
                        },
                        items: [
                          ItemConfig(
                              icon: _badgedIcon(Icons.chat_bubble_outline, 8),
                              title: '消息'),
                          ItemConfig(
                              icon: const Icon(Icons.groups_outlined),
                              title: '群聊'),
                          ItemConfig(
                              icon: _badgedIcon(Icons.contacts_outlined, 128),
                              title: '通讯录'),
                          ItemConfig(
                              icon: const Icon(
                                  Icons.account_balance_wallet_outlined),
                              title: '钱包'),
                          ItemConfig(
                              icon: const Icon(Icons.person_outline),
                              title: '我的'),
                        ],
                      )),
                    )),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('bottom surface meets safe area without extra gap',
      (tester) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await pumpNavigation(tester, platform: platform);
      final bar = tester.getRect(find.byType(GlassBottomNavBar));
      final surface = find.descendant(
          of: find.byType(GlassBottomNavBar),
          matching: find.byType(LiquidGlassSurface));
      expect(bar.bottom, 812);
      expect(tester.getRect(surface),
          Rect.fromLTWH(bar.left + 12, bar.top, bar.width - 24, 56));
      expect(bar.height, kBottomNavigationBarHeight + 34);
      expect(tester.getRect(find.byType(BottomNavigationBar)).bottom, 812 - 34);
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} mode changes preserve large-text geometry',
        (tester) async {
      await pumpNavigation(tester, brightness: brightness, scale: 2);
      final bar = tester.getRect(find.byType(GlassBottomNavBar));
      final label = tester.getRect(find.text('通讯录').hitTestable().first);
      final style =
          tester.widget<Text>(find.text('通讯录').hitTestable().first).style;
      await NavigationGlassController.instance
          .setMode(NavigationGlassMode.translucent);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(GlassBottomNavBar)), bar);
      expect(tester.getRect(find.text('通讯录')), label);
      expect(tester.widget<Text>(find.text('通讯录')).style, style);
      expect(tester.takeException(), isNull);
    });
    testWidgets('${brightness.name} glass respects safe areas and selection',
        (tester) async {
      var selected = -1;
      await pumpNavigation(tester,
          brightness: brightness, onSelected: (value) => selected = value);
      expect(
          find.byType(BackdropFilter).evaluate().length +
              find.byType(glass.GlassContainer).evaluate().length,
          2);
      expect(find.byType(LiquidGlassSurface), findsNWidgets(2));
      expect(tester.getRect(find.byType(GlassAppBar)).bottom, greaterThan(44));
      final bar = find.byType(BottomNavigationBar);
      expect(tester.getRect(bar).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(bar).bottom, lessThanOrEqualTo(812 - 34));
      await tester.tap(find.text('通讯录').hitTestable().first);
      expect(selected, 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
          '${brightness.name} ${platform.name} home capsule keeps five tabs and badges at large text',
          (tester) async {
        for (final scale in [1.0, 2.0]) {
          await pumpNavigation(tester,
              brightness: brightness, platform: platform, scale: scale);
          final bar = tester.getRect(find.byType(GlassBottomNavBar));
          final capsule = tester.getRect(_bottomSurface());
          expect(bar, const Rect.fromLTWH(0, 722, 375, 90));
          expect(capsule, const Rect.fromLTWH(12, 722, 351, 56));
          expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .items,
              hasLength(5));
          expect(find.byType(UnreadCountView), findsNWidgets(2));
          for (final value in ['8', '99+']) {
            final badgeText = find.descendant(
                of: find.byType(BottomNavigationBar),
                matching: find.text(value));
            expect(badgeText, findsOneWidget);
            final badge = tester.getRect(badgeText);
            expect(badge.left, greaterThanOrEqualTo(capsule.left));
            expect(badge.right, lessThanOrEqualTo(capsule.right));
            expect(badge.top, greaterThanOrEqualTo(capsule.top));
            expect(badge.bottom, lessThanOrEqualTo(capsule.bottom));
          }
          for (final label in ['消息', '群聊', '通讯录', '钱包', '我的']) {
            final destination = find.descendant(
                of: find.byType(BottomNavigationBar),
                matching: find.text(label));
            expect(destination.hitTestable(), findsOneWidget);
            final labelRect = tester.getRect(destination);
            expect(labelRect.left, greaterThanOrEqualTo(capsule.left));
            expect(labelRect.right, lessThanOrEqualTo(capsule.right));
            expect(labelRect.bottom, lessThanOrEqualTo(capsule.bottom));
          }
          await _exportNavigation(tester,
              'home-glass-${brightness.name}-${platform.name}-text${scale.toInt()}');
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('actual home shader paints or explicitly reports its fallback',
      (tester) async {
    final available = await NavigationGlassController.instance
        .setMode(NavigationGlassMode.liquid);
    if (!available) {
      await NavigationGlassController.instance
          .setMode(NavigationGlassMode.translucent);
    }
    await pumpNavigation(tester, platform: TargetPlatform.android);
    if (!available) {
      expect(_hasLiquidBottom(), isFalse);
      expect(
          find.descendant(
              of: _bottomSurface(), matching: find.byType(BackdropFilter)),
          findsOneWidget);
      debugPrint(
          'HOME_GLASS_RENDERER: fallback; host shader initialization failed. '
          'This run does not validate liquid rendering.');
    } else {
      expect(
          find.descendant(
              of: _bottomSurface(),
              matching: find.byType(glass.GlassContainer)),
          findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final pixels =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          expect(pixels, isNotNull);
          expect(pixels!.lengthInBytes, greaterThan(0));
        } finally {
          image.dispose();
        }
      });
      debugPrint(
          'HOME_GLASS_RENDERER: liquid; real shader and raster completed.');
    }
    await _exportNavigation(tester, 'home-glass-shader-android');
    expect(tester.takeException(), isNull);
  });

  test('renderer failure preserves preference and can be retried', () async {
    var attempts = 0;
    final controller = NavigationGlassController(initialize: () async {
      if (++attempts == 1) throw StateError('shader unavailable');
    });
    addTearDown(controller.dispose);
    await controller.setMode(NavigationGlassMode.translucent);
    expect(await controller.setMode(NavigationGlassMode.liquid), isFalse);
    expect(controller.mode, NavigationGlassMode.translucent);
    expect(SpUtil().getString(NavigationGlassController.storageKey),
        'translucent');
    expect(await controller.setMode(NavigationGlassMode.liquid), isTrue);
    expect(controller.mode, NavigationGlassMode.liquid);
    expect(attempts, 2);
  });

  test('pending renderer does not override a newer mode choice', () async {
    final loading = Completer<void>();
    var attempts = 0;
    final controller = NavigationGlassController(initialize: () {
      attempts++;
      return loading.future;
    });
    addTearDown(controller.dispose);
    await controller.setMode(NavigationGlassMode.translucent);
    final first = controller.setMode(NavigationGlassMode.liquid);
    final second = controller.setMode(NavigationGlassMode.liquid);
    expect(controller.mode, NavigationGlassMode.translucent);
    await controller.setMode(NavigationGlassMode.translucent);
    loading.complete();
    await Future.wait([first, second]);
    expect(attempts, 1);
    expect(controller.mode, NavigationGlassMode.translucent);
    expect(SpUtil().getString(NavigationGlassController.storageKey),
        'translucent');
  });

  testWidgets('asymmetric top corners retain their full clip in both modes',
      (tester) async {
    const corners = BorderRadius.only(
        bottomLeft: Radius.circular(12), bottomRight: Radius.circular(20));
    for (final mode in [
      NavigationGlassMode.automatic,
      NavigationGlassMode.translucent
    ]) {
      await NavigationGlassController.instance.setMode(mode);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
        body: LiquidGlassSurface(
            borderRadius: corners, child: SizedBox(width: 200, height: 80)),
      )));
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<ClipRRect>(find.byType(ClipRRect))
              .any((clip) => clip.borderRadius == corners),
          isTrue);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('landscape, large text and reduced motion do not overflow',
      (tester) async {
    await pumpNavigation(tester,
        size: const Size(812, 375), scale: 2, reducedMotion: true);
    expect(tester.takeException(), isNull);
    for (final widget in tester.widgetList<AnimatedContainer>(find.descendant(
        of: find.byType(GlassBottomNavBar),
        matching: find.byType(AnimatedContainer)))) {
      expect(widget.duration, Duration.zero);
    }
  });

  testWidgets('high contrast uses opaque surfaces without blur',
      (tester) async {
    await pumpNavigation(tester, highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(glass.GlassContainer), findsNothing);
    expect(find.byType(glass.GlassBottomBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'persistent tabs retain scroll position and expose the last row above glass',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: PersistentTabView(
        navBarOverlap: const NavBarOverlap.full(),
        screenTransitionAnimation: const ScreenTransitionAnimation.none(),
        navBarBuilder: (config) => GlassBottomNavBar(config: config),
        tabs: [
          PersistentTabConfig(
            item: ItemConfig(icon: const Icon(Icons.chat), title: 'Messages'),
            screen: Builder(
                builder: (context) => Scaffold(
                      body: ListView.builder(
                        controller: scroll,
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom),
                        itemCount: 30,
                        itemExtent: 64,
                        itemBuilder: (_, index) => Text('Row $index'),
                      ),
                    )),
          ),
          PersistentTabConfig(
            item: ItemConfig(icon: const Icon(Icons.person), title: 'Me'),
            screen: const Scaffold(body: Text('Profile')),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final position = scroll.offset;
    expect(tester.getRect(find.text('Row 29')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(GlassBottomNavBar)).top));
    await tester.tap(find.text('Me').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.text('Messages').hitTestable().first);
    await tester.pumpAndSettle();
    expect(scroll.offset, position);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('shared TitleBar keeps its back action with the glass material',
      (tester) async {
    var backs = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          home: Scaffold(
        appBar: TitleBar.back(title: 'Details', onTap: () => backs++),
        body: const SizedBox.expand(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassSurface), findsOneWidget);
    await tester.tap(find
        .descendant(
            of: find.byType(TitleBar), matching: find.byType(GestureDetector))
        .first);
    expect(backs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Android keeps general bars frosted and restores its saved quality choice',
      (tester) async {
    await pumpNavigation(tester, platform: TargetPlatform.android);
    expect(find.byType(glass.GlassBottomBar), findsNothing);
    final topSurface = find.descendant(
        of: find.byType(GlassAppBar),
        matching: find.byType(LiquidGlassSurface));
    expect(
        find.descendant(
            of: topSurface, matching: find.byType(glass.GlassContainer)),
        findsNothing);
    expect(
        find.descendant(of: topSurface, matching: find.byType(BackdropFilter)),
        findsOneWidget);
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
    await tester.pumpAndSettle();
    expect(find.byType(glass.GlassBottomBar), findsNothing);
    expect(find.byType(glass.GlassContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    final restored = NavigationGlassController()..load();
    expect(restored.mode, NavigationGlassMode.translucent);
    restored.dispose();
    expect(tester.takeException(), isNull);
  });
}
