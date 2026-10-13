import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/routes/swipe_back/app_get_transition.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:openim/routes/swipe_back/app_route_depth_transition.dart';
import 'package:openim/routes/swipe_back/app_swipe_back_tokens.dart';

import 'app_swipe_back_test.dart' as support;

class _Owner extends GetxController {
  int closes = 0;
  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({required this.onInit, required this.scroll});
  final VoidCallback onInit;
  final ScrollController scroll;

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      key: const ValueKey('under-page'),
      body: ListView.builder(
          controller: widget.scroll,
          itemCount: 100,
          itemExtent: 50,
          itemBuilder: (_, index) => Text('item $index')));
}

double pageOffset(WidgetTester tester, String name) {
  final depth = find.byElementPredicate(
      (element) =>
          element.widget is AppRouteDepthTransition &&
          ModalRoute.of(element)?.settings.name == name,
      skipOffstage: false);
  final transforms = find.descendant(
      of: depth,
      matching: find.byType(Scaffold, skipOffstage: false),
      skipOffstage: false);
  return tester.getTopLeft(transforms.first).dx;
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  test('production route table has chat edges and excludes root screens', () {
    for (final page in AppPages.routes) {
      expect(page.customTransition, isA<AppGetTransition>());
      final transition = page.customTransition! as AppGetTransition;
      expect(page.popGesture, isFalse,
          reason: 'avoid duplicate GetX recognizer');
      expect(transition.edgeWidth,
          AppRoutes.isConversationRoute(page.name) ? 40 : 24);
      expect(
          transition.enableBackGesture,
          ![AppRoutes.home, AppRoutes.login, AppRoutes.splash]
              .contains(page.name));
      expect(page.transitionDuration, AppSwipeBackTokens.transitionDuration);
    }
  });

  testWidgets('GetX and shared routes slide, reverse and preserve list state',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var initializations = 0;
    await tester.pumpWidget(GetMaterialApp(
      customTransition: AppGetTransition(),
      popGesture: false,
      home: const Scaffold(body: Text('home')),
    ));
    final nav = Get.key.currentState!;
    final owner = _Owner();
    unawaited(nav.push(GetPageRoute<void>(
        settings: const RouteSettings(name: '/under'),
        binding: BindingsBuilder(() {
          Get.put<_Owner>(owner);
        }),
        customTransition: AppGetTransition(),
        popGesture: false,
        page: () {
          Get.find<_Owner>();
          return _CounterPage(onInit: () => initializations++, scroll: scroll);
        })));
    await tester.pumpAndSettle();
    scroll.jumpTo(425);
    await tester.pump();
    unawaited(nav.push(AppMaterialPageRoute<void>(
      settings: const RouteSettings(name: '/middle'),
      builder: (_) => const Scaffold(body: Text('middle')),
    )));
    await tester.pumpAndSettle();
    expect(pageOffset(tester, '/under'), closeTo(-93.75, .001));
    expect(owner.closes, 0);
    expect(initializations, 1);
    expect(scroll.offset, 425);
    unawaited(Get.to<void>(() => support.target));
    await tester.pumpAndSettle();
    expect(pageOffset(tester, '/middle'), closeTo(-93.75, .001));
    await support.swipe(tester);
    expect(pageOffset(tester, '/middle'), closeTo(0, .001));
    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(pageOffset(tester, '/under'), closeTo(-56.25, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(pageOffset(tester, '/under'), closeTo(-93.75, .001));
    await support.swipe(tester);
    expect(pageOffset(tester, '/under'), closeTo(0, .001));
    expect(initializations, 1);
    expect(scroll.offset, 425);
    expect(owner.closes, 0);
    await support.swipe(tester);
    expect(owner.closes, 1);
    expect(Get.isRegistered<_Owner>(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GetX blocked edits and explicit no-swipe pages stay in place',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
        customTransition: AppGetTransition(),
        popGesture: false,
        home: const Scaffold(body: Text('home'))));
    for (final veto in [false, true]) {
      final route = GetPageRoute<void>(
          popGesture: false,
          customTransition: AppGetTransition(enableBackGesture: veto),
          page: () => PopScope<void>(canPop: !veto, child: support.target));
      unawaited(Get.key.currentState!.push(route));
      await tester.pumpAndSettle();
      await support.swipe(tester, distance: 350);
      expect(find.byKey(support.pageKey), findsOneWidget);
      Get.key.currentState!.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('transparent route keeps its underlying content visible',
      (tester) async {
    final nav = await support.host(tester);
    final route = AppMaterialPageRoute<void>(
      opaque: false,
      edgeStartWidthPx: 96,
      builder: (_) => const Center(child: Text('overlay')),
    );
    unawaited(nav.currentState!.push(route));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await support.swipe(tester, start: 90, distance: 180);
    expect(find.text('overlay'), findsNothing);
  });
}
