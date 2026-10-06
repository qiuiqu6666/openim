import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  setUp(() async {
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  Future<void> pumpSurface(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    NavigationGlassSurface surface = NavigationGlassSurface.top,
    Color? tint,
    bool highContrast = false,
    bool reducedMotion = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme:
          ThemeData(brightness: brightness, platform: TargetPlatform.android),
      home: MediaQuery(
        data: MediaQueryData(
          highContrast: highContrast,
          disableAnimations: reducedMotion,
        ),
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: ColoredBox(color: Colors.red.shade800)),
                      Expanded(child: ColoredBox(color: Colors.blue.shade800)),
                    ]),
              ),
              Positioned(
                left: 12,
                top: 32,
                child: LiquidGlassSurface(
                  surface: surface,
                  tint: tint,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(width: 240, height: 80),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder surfaceTint() => find
      .descendant(
        of: find.byType(LiquidGlassSurface),
        matching: find.byType(ColoredBox),
      )
      .first;

  for (final brightness in Brightness.values) {
    for (final surface in NavigationGlassSurface.values) {
      testWidgets('${brightness.name} ${surface.name} clips its frosted blur',
          (tester) async {
        await pumpSurface(tester, brightness: brightness, surface: surface);
        final blur = find.byType(BackdropFilter);
        expect(blur, findsOneWidget);
        expect(tester.getRect(blur), const Rect.fromLTWH(12, 32, 240, 80));
        expect(
          find.ancestor(of: blur, matching: find.byType(ClipRRect)),
          findsOneWidget,
        );
        final filter = tester.widget<BackdropFilter>(blur).filter;
        final sigma = surface == NavigationGlassSurface.top ? 18.0 : 20.0;
        expect(
            filter,
            ui.ImageFilter.blur(
                sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
        final color = tester.widget<ColoredBox>(surfaceTint()).color;
        expect(color.a, inExclusiveRange(0.0, 1.0));
        expect(
            color.a, closeTo(brightness == Brightness.light ? .76 : .70, .01));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${brightness.name} high contrast keeps an opaque clipped bar',
        (tester) async {
      await pumpSurface(tester,
          brightness: brightness, highContrast: true, tint: Colors.transparent);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(tester.widget<ColoredBox>(surfaceTint()).color.a, 1.0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('explicit tint keeps its color but receives navigation opacity',
      (tester) async {
    const tint = Color(0xFFCD4B38);
    await pumpSurface(tester, tint: tint);
    final color = tester.widget<ColoredBox>(surfaceTint()).color;
    expect(color.r, tint.r);
    expect(color.g, tint.g);
    expect(color.b, tint.b);
    expect(color.a, closeTo(.76, .01));
  });

  testWidgets('reduced motion keeps a static frosted surface', (tester) async {
    await pumpSurface(tester, reducedMotion: true);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.widget<ColoredBox>(surfaceTint()).color.a,
        inExclusiveRange(0.0, 1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit AppBar background tints its glass without covering it',
      (tester) async {
    var actions = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          appBar: GlassAppBar(
            backgroundColor: Colors.black,
            title: const Text('Detail'),
            actions: [
              IconButton(
                onPressed: () => actions++,
                icon: const Icon(Icons.more_horiz),
                tooltip: 'More',
              ),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<GlassAppBar>(find.byType(GlassAppBar)).backgroundColor,
        Colors.transparent);
    expect(find.byType(LiquidGlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final color = tester.widget<ColoredBox>(surfaceTint()).color;
    expect(color.r, 0);
    expect(color.g, 0);
    expect(color.b, 0);
    expect(color.a, inExclusiveRange(0.0, 1.0));
    await tester.tap(find.byTooltip('More'));
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppBar frost samples and softens the live content behind it',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const boundaryKey = ValueKey('navigation-paint');

    Future<void> pumpScene({required bool swapped}) async {
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              extendBodyBehindAppBar: true,
              appBar: GlassAppBar(automaticallyImplyLeading: false),
              body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        child: ColoredBox(
                            color: swapped ? Colors.blue : Colors.red)),
                    Expanded(
                        child: ColoredBox(
                            color: swapped ? Colors.red : Colors.blue)),
                  ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<List<int>> rgbAt(int x, int y) async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      return tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (y * image.width + x) * 4;
        final rgb = [
          for (var channel = 0; channel < 3; channel++)
            data!.getUint8(offset + channel)
        ];
        image.dispose();
        return rgb;
      }).then((value) => value!);
    }

    await pumpScene(swapped: false);
    final farFromEdge = await rgbAt(40, 28);
    final nearEdge = await rgbAt(180, 28);
    // The left half is red; blue from the right must blend across the edge.
    expect(nearEdge[2], greaterThan(farFromEdge[2] + 8));
    await pumpScene(swapped: true);
    final changedBackdrop = await rgbAt(40, 28);
    expect(changedBackdrop[2], greaterThan(farFromEdge[2] + 40));
    expect(changedBackdrop[0], lessThan(farFromEdge[0] - 40));
    expect(tester.takeException(), isNull);
  });
}
