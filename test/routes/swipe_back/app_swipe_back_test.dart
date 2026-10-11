import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/routes/swipe_back/app_get_transition.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:openim/routes/swipe_back/app_page_transitions_theme.dart';
import 'package:openim/routes/swipe_back/app_swipe_back_tokens.dart';

const pageKey = ValueKey('swipe-target');
const target = Scaffold(key: pageKey, body: Text('target'));

Future<void> swipe(WidgetTester tester,
    {double start = 10, double distance = 80, bool cancel = false}) async {
  final gesture = await tester.startGesture(Offset(start, 300));
  await gesture.moveBy(Offset(distance, 0),
      timeStamp: const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 50));
  if (cancel) {
    await gesture.cancel();
  } else {
    await gesture.up();
  }
  await tester.pumpAndSettle();
}

Future<GlobalKey<NavigatorState>> host(WidgetTester tester,
    {TargetPlatform platform = TargetPlatform.android,
    Brightness brightness = Brightness.light}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigator,
    theme: ThemeData(
      platform: platform,
      brightness: brightness,
      pageTransitionsTheme: appPageTransitionsTheme,
    ),
    home: const Scaffold(body: Text('home')),
  ));
  return navigator;
}

Future<void> push(WidgetTester tester, GlobalKey<NavigatorState> navigator,
    {Widget child = target, double edge = 24, bool enabled = true}) async {
  unawaited(navigator.currentState!.push(AppMaterialPageRoute<void>(
    builder: (_) => child,
    edgeStartWidthPx: edge,
    enableFullScreenBackGesture: enabled,
  )));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(375, 812);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets('$platform $brightness pops at 16 percent, below half screen',
          (tester) async {
        final nav =
            await host(tester, platform: platform, brightness: brightness);
        await push(tester, nav);
        await swipe(tester);
        expect(find.byKey(pageKey), findsNothing);
        expect(nav.currentState!.userGestureInProgress, isFalse);
      });
    }
  }

  testWidgets('short slow drag snaps back then a short fast flick returns',
      (tester) async {
    final nav = await host(tester);
    await push(tester, nav);
    await swipe(tester, distance: 40);
    expect(find.byKey(pageKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(pageKey)).dx, 0);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    await tester.flingFrom(const Offset(10, 300), const Offset(40, 0), 700);
    await tester.pumpAndSettle();
    expect(find.byKey(pageKey), findsNothing);
  });

  testWidgets('normal 24, chat 40 and funds 96 edges exclude the page body',
      (tester) async {
    final nav = await host(tester);
    for (final edge in [24.0, 40.0, 96.0]) {
      await push(tester, nav, edge: edge);
      await swipe(tester, start: edge + 5);
      expect(find.byKey(pageKey), findsOneWidget);
      await swipe(tester, start: edge - 5);
      expect(find.byKey(pageKey), findsNothing);
    }
  });

  testWidgets(
      'cancelled pointer never returns even past the distance threshold',
      (tester) async {
    final nav = await host(tester);
    await push(tester, nav);
    await swipe(tester, distance: 150, cancel: true);
    expect(find.byKey(pageKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(pageKey)).dx, 0);
    expect(nav.currentState!.userGestureInProgress, isFalse);
  });

  testWidgets('PopScope blocks return and re-enables without recreating route',
      (tester) async {
    final nav = await host(tester);
    final allowed = ValueNotifier(false);
    addTearDown(allowed.dispose);
    await push(tester, nav,
        child: ValueListenableBuilder(
            valueListenable: allowed,
            builder: (_, canPop, child) => PopScope<void>(
                  canPop: canPop,
                  child: child!,
                ),
            child: target));
    await swipe(tester, distance: 300);
    expect(find.byKey(pageKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(pageKey)).dx, 0);
    allowed.value = true;
    await tester.pump();
    await swipe(tester);
    expect(find.byKey(pageKey), findsNothing);
  });

  testWidgets(
      'a veto enabled during drag restores the route instead of popping',
      (tester) async {
    final nav = await host(tester);
    final allowed = ValueNotifier(true);
    addTearDown(allowed.dispose);
    await push(tester, nav,
        child: ValueListenableBuilder(
            valueListenable: allowed,
            builder: (_, canPop, __) =>
                PopScope<void>(canPop: canPop, child: target)));
    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    allowed.value = false;
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(pageKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(pageKey)).dx, 0);
    expect(nav.currentState!.userGestureInProgress, isFalse);
  });

  testWidgets('root, disabled route and local history do not edge-pop',
      (tester) async {
    final nav = await host(tester);
    await swipe(tester, distance: 300);
    expect(find.text('home'), findsOneWidget);
    await push(tester, nav, enabled: false);
    await swipe(tester);
    expect(find.byKey(pageKey), findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    final route = AppMaterialPageRoute<void>(builder: (_) => target);
    unawaited(nav.currentState!.push(route));
    await tester.pumpAndSettle();
    route.addLocalHistoryEntry(LocalHistoryEntry());
    await swipe(tester);
    expect(route.willHandlePopInternally, isTrue);
    expect(find.byKey(pageKey), findsOneWidget);
  });

  testWidgets(
      'vertical list scroll and horizontal content outside edge still work',
      (tester) async {
    final nav = await host(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var horizontalDrags = 0;
    await push(tester, nav,
        child: Scaffold(
            key: pageKey,
            body: GestureDetector(
              onHorizontalDragUpdate: (_) => horizontalDrags++,
              child: ListView.builder(
                  controller: scroll,
                  itemCount: 80,
                  itemBuilder: (_, index) =>
                      SizedBox(height: 60, child: Text('row $index'))),
            )));
    await tester.dragFrom(const Offset(10, 400), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.dragFrom(const Offset(100, 300), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(horizontalDrags, greaterThan(0));
    expect(find.byKey(pageKey), findsOneWidget);
  });

  testWidgets('second finger cannot steal the active edge drag',
      (tester) async {
    final nav = await host(tester);
    await push(tester, nav);
    final first = await tester.startGesture(const Offset(10, 300), pointer: 1);
    await first.moveBy(const Offset(20, 0));
    final second = await tester.startGesture(const Offset(12, 500), pointer: 2);
    await second.moveBy(const Offset(150, 0));
    await second.up();
    await first.cancel();
    await tester.pumpAndSettle();
    expect(find.byKey(pageKey), findsOneWidget);
    expect(nav.currentState!.userGestureInProgress, isFalse);
  });

  testWidgets('toolbar pop during an active drag does not revive the page',
      (tester) async {
    final nav = await host(tester);
    await push(tester, nav);
    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(30, 0));
    nav.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byKey(pageKey), findsNothing);
    expect(nav.currentState!.userGestureInProgress, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GetX named and anonymous routes use the same edge behavior',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      customTransition: AppGetTransition(),
      popGesture: false,
      transitionDuration: AppSwipeBackTokens.transitionDuration,
      home: const Scaffold(body: Text('home')),
      getPages: [
        GetPage(
            name: '/chat-test',
            page: () => target,
            popGesture: false,
            customTransition: AppGetTransition(edgeWidth: 40)),
      ],
    ));
    unawaited(Get.toNamed<void>('/chat-test'));
    await tester.pumpAndSettle();
    await swipe(tester, start: 35);
    expect(find.byKey(pageKey), findsNothing);
    unawaited(Get.to<void>(() => target));
    await tester.pumpAndSettle();
    await swipe(tester);
    expect(find.byKey(pageKey), findsNothing);
    expect(Get.key.currentState!.userGestureInProgress, isFalse);
  });

  testWidgets('themed Material routes swipe; media and modal routes opt out',
      (tester) async {
    final nav = await host(tester);
    for (final type in ['normal', 'media', 'modal']) {
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
        settings: RouteSettings(
            name: type == 'media' ? AppSwipeBackTokens.mediaRouteName : type),
        fullscreenDialog: type == 'modal',
        builder: (_) => target,
      )));
      await tester.pumpAndSettle();
      await swipe(tester);
      expect(find.byKey(pageKey),
          type == 'normal' ? findsNothing : findsOneWidget);
      if (type != 'normal') {
        nav.currentState!.pop();
        await tester.pumpAndSettle();
      }
    }
  });
}
