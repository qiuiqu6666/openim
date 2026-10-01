import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/mine/mine_logic.dart';
import 'package:openim/pages/mine/mine_view.dart';
import 'nickname_edit_entry_test.dart'
    show NicknameIMFixture, NicknameMineFixture;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/home/glass_bottom_nav_bar.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await glass.LiquidGlassWidgets.initialize();
    const fontDirectory = String.fromEnvironment('GLASS_PREVIEW_FONTS');
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
        platform: platform,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF), brightness: brightness),
        brightness: brightness);
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
            child: Scaffold(
              extendBody: true,
              appBar: GlassAppBar(title: const Text('Messages'), actions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.add))
              ]),
              body: ListView.builder(
                itemCount: 16,
                itemBuilder: (_, index) => ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text('Conversation ${index + 1}'),
                  subtitle: const Text('A new message'),
                ),
              ),
              bottomNavigationBar: GlassBottomNavBar(
                  config: NavBarConfig(
                selectedIndex: 0,
                onItemSelected: onSelected ?? (_) {},
                items: [
                  ItemConfig(
                      icon: const Icon(Icons.chat_bubble_outline),
                      title: 'Messages'),
                  ItemConfig(
                      icon: const Icon(Icons.groups_outlined), title: 'Groups'),
                  ItemConfig(
                      icon: const Icon(Icons.contacts_outlined),
                      title: 'Contacts'),
                  ItemConfig(
                      icon: const Icon(Icons.person_outline), title: 'Me'),
                ],
              )),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} glass respects safe areas and selection',
        (tester) async {
      var selected = -1;
      await pumpNavigation(tester,
          brightness: brightness, onSelected: (value) => selected = value);
      expect(find.byType(glass.GlassContainer), findsWidgets);
      expect(find.byType(glass.GlassBottomBar), findsOneWidget);
      expect(tester.getRect(find.byType(GlassAppBar)).bottom, greaterThan(44));
      final button =
          find.widgetWithText(GestureDetector, 'Contacts').hitTestable().first;
      expect(tester.getRect(button).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(812 - 34));
      await tester.tap(button);
      expect(selected, 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Optional visual evidence, never part of production data.
      if (const bool.fromEnvironment('GLASS_PREVIEW')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/openim-glass-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

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
      'Android defaults to shader-free bars and saves explicit quality choice',
      (tester) async {
    await pumpNavigation(tester, platform: TargetPlatform.android);
    expect(find.byType(glass.GlassBottomBar), findsNothing);
    expect(find.byType(glass.GlassContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.liquid);
    await tester.pumpAndSettle();
    expect(find.byType(glass.GlassBottomBar), findsOneWidget);
    expect(SpUtil().getString(NavigationGlassController.storageKey), 'liquid');
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
    await tester.pumpAndSettle();
    expect(find.byType(glass.GlassBottomBar), findsNothing);
    expect(find.byType(glass.GlassContainer), findsNothing);
    final restored = NavigationGlassController()..load();
    expect(restored.mode, NavigationGlassMode.translucent);
    restored.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Mine exposes a working persisted glass quality picker',
      (tester) async {
    addTearDown(Get.reset);
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final im = NicknameIMFixture();
    Get.put<IMController>(im);
    Get.put<MineLogic>(NicknameMineFixture(im));
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MinePage(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导航玻璃效果'));
    await tester.pumpAndSettle();
    expect(find.text('液态玻璃'), findsOneWidget);
    await tester.tap(find.text('普通半透明'));
    await tester.pumpAndSettle();
    expect(NavigationGlassController.instance.mode,
        NavigationGlassMode.translucent);
    expect(SpUtil().getString(NavigationGlassController.storageKey),
        'translucent');
    expect(find.text('普通半透明'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
