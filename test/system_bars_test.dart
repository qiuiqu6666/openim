import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_composer_palette.dart';
import 'package:openim_common/src/widgets/chat/voice/chat_voice_panel_view.dart';
import 'package:openim/pages/home/glass_bottom_nav_bar.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
    final font = Platform.environment['SYSTEM_BARS_FONT'];
    if (font != null) {
      await (FontLoader('AuditFont')
            ..addFont(File(font)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes))))
          .load();
    }
  });
  test(
      'transparent bars choose icons from each background without contrast scrims',
      () {
    final style = AppSystemBars.styleFor(Colors.black,
        navigationBackground: Colors.white);
    expect(style.statusBarColor, Colors.transparent);
    expect(style.systemNavigationBarColor, Colors.transparent);
    expect(style.systemNavigationBarDividerColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.systemStatusBarContrastEnforced, false);
    expect(style.systemNavigationBarContrastEnforced, false);
  });
  test('Android startup explicitly requests edge-to-edge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await AppSystemBars.initialize();
    expect(calls.single.method, 'SystemChrome.setEnabledSystemUIMode');
    expect(calls.single.arguments, 'SystemUiMode.edgeToEdge');
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets(
          'page paints both system-bar insets in $platform / dark=$dark',
          (tester) async {
        final previousDark = Styles.isDark;
        Styles.isDark = dark;
        addTearDown(() => Styles.isDark = previousDark);
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
        addTearDown(tester.view.reset);
        final surface = dark ? const Color(0xFF202A36) : Colors.white;
        final background =
            dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA);
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => MaterialApp(
                  theme: ThemeData(
                      brightness: dark ? Brightness.dark : Brightness.light,
                      platform: platform,
                      fontFamily: 'AuditFont'),
                  home: RepaintBoundary(
                      key: const ValueKey('system-bars-preview'),
                      child: AppSystemBars(
                        background: surface,
                        navigationBackground: background,
                        child: Scaffold(
                          backgroundColor: background,
                          appBar: TitleBar.back(
                              title: 'Profile', backgroundColor: surface),
                          body: SafeArea(
                              top: false,
                              child: Column(children: [
                                Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Card(
                                        child: ListTile(
                                            title:
                                                const Text('Page background'),
                                            subtitle: const Text(
                                                'Safe area stays inside the page')))),
                                const Spacer(),
                                const SizedBox(
                                    height: 48,
                                    child: Center(
                                        child: Text('Bottom action',
                                            key: ValueKey('action')))),
                              ])),
                        ),
                      )),
                )));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(Scaffold)).bottom, 812);
        expect(tester.getRect(find.byKey(const ValueKey('action'))).bottom,
            lessThanOrEqualTo(778));
        expect(SystemChrome.latestStyle!.statusBarColor, Colors.transparent);
        expect(SystemChrome.latestStyle!.systemNavigationBarColor,
            Colors.transparent);
        expect(SystemChrome.latestStyle!.statusBarIconBrightness,
            dark ? Brightness.light : Brightness.dark);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('system-bars-preview')));
        final image =
            (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
        final raw = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        Color pixel(int x, int y) {
          final offset = (y * image.width + x) * 4;
          return Color.fromARGB(raw.getUint8(offset + 3), raw.getUint8(offset),
              raw.getUint8(offset + 1), raw.getUint8(offset + 2));
        }

        final topTint = NavigationGlassTokens.frostedTint(
            tester.element(find.byType(TitleBar)),
            tint: surface);
        final expectedTop = Color.alphaBlend(topTint, background).toARGB32();
        final paintedTop = pixel(2, 2).toARGB32();
        // The translucent tint composites over the page background. Allow
        // one byte of rounding in the raster backend's premultiplied channels.
        expect(paintedTop >> 24, 255);
        for (final shift in [16, 8, 0]) {
          expect((paintedTop >> shift) & 255,
              closeTo((expectedTop >> shift) & 255, 1));
        }
        expect(pixel(2, 808), background);
        final previews = Platform.environment['SYSTEM_BARS_PREVIEW'];
        if (previews != null && platform == TargetPlatform.android) {
          final png = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png)))!;
          await tester.runAsync(() async {
            await Directory(previews).create(recursive: true);
            await File('$previews/${dark ? "dark" : "light"}.png')
                .writeAsBytes(png.buffer.asUint8List());
          });
        }
        image.dispose();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('nested page styles restore on back and change with theme',
      (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    Widget page(Color background) => AppSystemBars(
        background: background,
        child: Scaffold(
            backgroundColor: background,
            appBar: AppBar(
                backgroundColor: background,
                systemOverlayStyle: AppSystemBars.styleFor(background)),
            body: const SafeArea(child: Text('Route'))));
    await tester
        .pumpWidget(MaterialApp(navigatorKey: nav, home: page(Colors.white)));
    await tester.pumpAndSettle();
    nav.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => page(Colors.black)));
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.light);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.dark);
    await tester.pumpWidget(MaterialApp(home: page(Colors.black)));
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.light);
  });
  for (final dark in [false, true]) {
    testWidgets('chat footer stays safe with panels and keyboard / dark=$dark',
        (tester) async {
      final previousDark = Styles.isDark;
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = previousDark);
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.reset);
      final micKey = GlobalKey();
      var toolCalls = 0;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
            body: Column(children: [
              const Expanded(child: SizedBox()),
              ChatInputBox(
                toolbox: ChatToolBox(onTapFile: () => toolCalls++),
                onTapVoice: () {},
                voiceRecordBar: Builder(
                    builder: (context) => ChatVoiceIdlePanel(
                          height: 248 + MediaQuery.paddingOf(context).bottom,
                          micKey: micKey,
                        )),
              ),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final input = find.byType(ChatInputBox);
      final footerBox =
          find.descendant(of: input, matching: find.byType(ColoredBox)).first;
      final surface = chatComposerSurface(tester.element(input));
      expect(tester.widget<ColoredBox>(footerBox).color, surface);
      expect(tester.getRect(input).bottom, 812);
      expect(tester.getRect(find.byType(ChatTextField)).bottom,
          lessThanOrEqualTo(778));
      await tester.tap(find.byTooltip(StrRes.add));
      await tester.pumpAndSettle();
      // Expanded panels paint through the home-indicator area; their actionable
      // content keeps the safe inset inside the panel, rather than outside it.
      final toolboxPanel = find.byKey(const ValueKey('chat-toolbox-panel'));
      expect(tester.getRect(toolboxPanel).bottom, 812);
      expect(
          (tester.widget<Container>(toolboxPanel).decoration as BoxDecoration)
              .color,
          ChatToolboxTokens.panelBackground(tester.element(toolboxPanel)));
      final fileAction = find.byKey(const ValueKey('chat-toolbox-action-file'));
      expect(tester.getRect(fileAction).bottom, lessThanOrEqualTo(778));
      await tester.tap(fileAction);
      expect(toolCalls, 1);
      expect(tester.widget<ColoredBox>(footerBox).color,
          ChatToolboxTokens.panelBackground(tester.element(input)));
      await tester.tap(find.byTooltip(StrRes.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(StrRes.voiceCapture));
      await tester.pumpAndSettle();
      final voicePanel = find.byKey(const ValueKey('chat-voice-idle-panel'));
      expect(tester.getRect(voicePanel).bottom, 812);
      expect(tester.widget<ColoredBox>(voicePanel).color, surface);
      expect(tester.getRect(find.byKey(micKey)).bottom, lessThanOrEqualTo(778));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('chat-voice-idle-title')))
              .bottom,
          lessThanOrEqualTo(778));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('chat-voice-idle-hint')))
              .bottom,
          lessThanOrEqualTo(778));
      await tester
          .tap(find.byKey(const ValueKey('chat-voice-input-placeholder')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      expect(tester.getRect(input).bottom, 512);
      expect(tester.getRect(find.byType(ChatTextField)).bottom,
          lessThanOrEqualTo(512));
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      await tester.pumpAndSettle();
      expect(tester.getRect(input).bottom, 812);
      expect(SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
          dark ? Brightness.light : Brightness.dark);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('a custom glass header overrides the global icon brightness',
      (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          appBarTheme: AppBarTheme(
        systemOverlayStyle: AppSystemBars.styleFor(Colors.white),
      )),
      home: Scaffold(appBar: GlassAppBar(backgroundColor: Colors.black)),
    ));
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle!.statusBarIconBrightness, Brightness.light);
    expect(SystemChrome.latestStyle!.statusBarBrightness, Brightness.dark);
  });
  testWidgets('login gradient fills the screen while its form stays safe',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Material(
        child: TouchCloseSoftKeyboard(
          isGradientBg: true,
          child: Column(children: [
            Text('Form header'),
            Spacer(),
            Text('Submit'),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final gradient = find.descendant(
        of: find.byType(TouchCloseSoftKeyboard),
        matching: find.byType(DecoratedBox));
    expect(tester.getRect(gradient).top, 0);
    expect(tester.getRect(gradient).bottom, 812);
    expect(
        tester.getRect(find.text('Form header')).top, greaterThanOrEqualTo(24));
    expect(tester.getRect(find.text('Submit')).bottom, lessThanOrEqualTo(778));
    expect(tester.takeException(), isNull);
  });
  testWidgets('home tab bar paints the home-indicator area without a gap',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            bottomNavigationBar: GlassBottomNavBar(
                config: NavBarConfig(
                    selectedIndex: 0,
                    onItemSelected: (_) {},
                    items: [
          ItemConfig(icon: const Icon(Icons.chat), title: 'Chat'),
          ItemConfig(icon: const Icon(Icons.person), title: 'Me')
        ])))));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(GlassBottomNavBar)).bottom, 812);
    expect(tester.getRect(find.byType(BottomNavigationBar)).bottom, 778);
    expect(
        SystemChrome.latestStyle!.systemNavigationBarColor, Colors.transparent);
    expect(
        SystemChrome.latestStyle!.systemNavigationBarContrastEnforced, false);
    expect(tester.takeException(), isNull);
  });
}
