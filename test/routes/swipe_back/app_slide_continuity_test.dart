import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/routes/swipe_back/app_get_transition.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:openim/routes/swipe_back/app_swipe_back_tokens.dart';
import 'app_swipe_back_test.dart' as support;

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);
  for (final kind in ['shared', 'material', 'get']) {
    testWidgets(
        '$kind parallax stays synchronized through push, drag and settlement',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final nav = await support.host(tester);
      const underKey = ValueKey('under');
      unawaited(nav.currentState!.push(AppMaterialPageRoute<void>(
          builder: (_) => const Scaffold(key: underKey))));
      await tester.pumpAndSettle();
      final PageRoute<void> route = switch (kind) {
        'material' => MaterialPageRoute<void>(builder: (_) => support.target),
        'get' => GetPageRoute<void>(
            page: () => support.target,
            customTransition: AppGetTransition(),
            popGesture: false,
            transitionDuration: AppSwipeBackTokens.transitionDuration),
        _ => AppMaterialPageRoute<void>(builder: (_) => support.target),
      };
      double topX() => tester.getTopLeft(find.byKey(support.pageKey)).dx;
      void parallax() {
        expect(
            tester.getTopLeft(find.byKey(underKey)).dx,
            closeTo(
                -(375 - topX()) * AppSwipeBackTokens.parallaxFraction, .01));
        expect(tester.getSize(find.byKey(underKey)).width, 375);
      }

      unawaited(nav.currentState!.push(route));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(topX(), inExclusiveRange(0, 375));
      parallax();
      await tester.pump(AppSwipeBackTokens.transitionDuration -
          const Duration(milliseconds: 80));
      expect(topX(), closeTo(0, .01));
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(const Offset(10, 300));
      await drag.moveBy(const Offset(100, 0),
          timeStamp: const Duration(milliseconds: 800));
      await tester.pump();
      expect(topX(), closeTo(100, .01));
      parallax();
      await drag.cancel();
      await tester.pump();
      expect(topX(), closeTo(100, .01));
      await tester.pump(const Duration(milliseconds: 40));
      expect(topX(), inExclusiveRange(0, 100));
      parallax();
      await tester.pumpAndSettle();
      expect(topX(), closeTo(0, .01));
      await tester.pump(const Duration(milliseconds: 1));
      expect(nav.currentState!.userGestureInProgress, isFalse);
      final finish = await tester.startGesture(const Offset(10, 300));
      await finish.moveBy(const Offset(100, 0),
          timeStamp: const Duration(milliseconds: 800));
      await tester.pump();
      await finish.up();
      await tester.pump();
      expect(topX(), closeTo(100, .01));
      await tester.pump(const Duration(milliseconds: 60));
      expect(topX(), inExclusiveRange(100, 375));
      parallax();
      await tester.pumpAndSettle();
      expect(find.byKey(support.pageKey), findsNothing);
      expect(tester.getTopLeft(find.byKey(underKey)).dx, closeTo(0, .01));
      expect(nav.currentState!.userGestureInProgress, isFalse);

      unawaited(nav.currentState!
          .push(AppMaterialPageRoute<void>(builder: (_) => support.target)));
      await tester.pumpAndSettle();
      await nav.currentState!.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      parallax();
      await tester.pumpAndSettle();
      expect(find.byKey(support.pageKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('return during entry does not jump position', (tester) async {
    final nav = await support.host(tester);
    final route = AppMaterialPageRoute<void>(builder: (_) => support.target);
    unawaited(nav.currentState!.push(route));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final before = tester.getTopLeft(find.byKey(support.pageKey)).dx;
    nav.currentState!.pop();
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(support.pageKey)).dx, closeTo(before, .01));
    await tester.pumpAndSettle();
    expect(find.byKey(support.pageKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled animations keep both pages stationary', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: const Scaffold()));
    const under = ValueKey('reduced-under');
    unawaited(nav.currentState!.push(AppMaterialPageRoute<void>(
        builder: (_) => const Scaffold(key: under))));
    await tester.pumpAndSettle();
    unawaited(nav.currentState!
        .push(AppMaterialPageRoute<void>(builder: (_) => support.target)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getTopLeft(find.byKey(under)).dx, 0);
    expect(tester.getTopLeft(find.byKey(support.pageKey)).dx, 0);
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(under)).dx, 0);
  });
}
