import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/loading/chat_initial_window_transition.dart';
import 'package:openim/pages/chat/navigation/chat_entry_route_timing.dart';
import 'package:openim/pages/chat/navigation/chat_entry_trace.dart';
import 'package:openim/routes/app_pages.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets('$platform $brightness: real taps work before entry settles',
          (tester) async {
        final nav = GlobalKey<NavigatorState>();
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final trace = ChatEntryTrace(1);
        var taps = 0;
        await tester.pumpWidget(MaterialApp(
            navigatorKey: nav,
            theme: ThemeData(platform: platform, brightness: brightness),
            home: const Scaffold()));
        final config =
            AppPages.routes.firstWhere((p) => p.name == AppRoutes.chat);
        final route = GetPageRoute<void>(
            customTransition: config.customTransition,
            transitionDuration: config.transitionDuration!,
            popGesture: false,
            page: () => ChatEntryRouteTiming(
                trace: trace,
                child: Scaffold(
                    body: ChatInitialWindowTransition(
                        loading: false,
                        skeleton: const Text('gray'),
                        observePaint: () => !trace.listInteractive,
                        onContentPainted: (ready) => trace.painted(
                            publishable: true,
                            hasVisibleMessages: true,
                            contentVisible: true,
                            canInteract: ready,
                            current: true),
                        child: ListView(
                            controller: scroll,
                            key: const ValueKey('list'),
                            children: [
                              TextButton(
                                  onPressed: () => taps++,
                                  child: const Text('tap message')),
                              ...List.generate(
                                  40,
                                  (i) => SizedBox(
                                      height: 48, child: Text('message $i')))
                            ])))));
        unawaited(nav.currentState!.push(route));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(trace.listInteractive, isTrue);
        expect(trace.transitionFinished, isFalse);
        expect(route.animation!.isCompleted, isFalse);
        await tester.tap(find.text('tap message'));
        expect(taps, 1,
            reason: 'Validate hit testing, not only a readiness flag');
        final list = tester.element(find.byKey(const ValueKey('list')));
        scroll.jumpTo(96);
        await tester.pumpAndSettle();
        expect(trace.complete, isTrue);
        expect(scroll.offset, 96);
        expect(tester.element(find.byKey(const ValueKey('list'))), same(list));
        expect(tester.takeException(), isNull);
        trace.close();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final reduceMotion in [false, true]) {
    testWidgets(
        'route completion does not wait for messages (reduce=$reduceMotion)',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final loading = ValueNotifier(true);
      addTearDown(loading.dispose);
      final trace = ChatEntryTrace(1);
      await tester.pumpWidget(MaterialApp(
          navigatorKey: nav,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: child!),
          home: const Scaffold()));
      final config =
          AppPages.routes.firstWhere((p) => p.name == AppRoutes.chat);
      unawaited(nav.currentState!.push(GetPageRoute<void>(
          customTransition: config.customTransition,
          transitionDuration: config.transitionDuration!,
          popGesture: false,
          page: () => ChatEntryRouteTiming(
              trace: trace,
              child: Scaffold(
                  body: ValueListenableBuilder<bool>(
                      valueListenable: loading,
                      builder: (_, waiting, __) => ChatInitialWindowTransition(
                          loading: waiting,
                          skeleton: const Text('gray'),
                          onContentPainted: (ready) => trace.painted(
                              publishable: !waiting,
                              hasVisibleMessages: true,
                              contentVisible: true,
                              canInteract: ready,
                              current: true),
                          child: const Text('real'))))))));
      await tester.pump();
      if (!reduceMotion) await tester.pumpAndSettle();
      expect(trace.transitionFinished, isTrue);
      expect(trace.listInteractive, isFalse);
      expect(trace.milliseconds.containsKey('first_correct_message_frame'),
          isFalse);
      if (!reduceMotion) nav.currentState!.didStartUserGesture();
      loading.value = false;
      await tester.pump();
      await tester.pumpAndSettle();
      if (!reduceMotion) {
        expect(trace.listInteractive, isFalse,
            reason: 'The navigator blocks message touches during a back gesture');
        nav.currentState!.didStopUserGesture();
        await tester.pump();
      }
      expect(trace.complete, isTrue);
      expect(trace.milliseconds['transition_finished']!,
          lessThanOrEqualTo(trace.milliseconds['list_interactive']!));
      trace.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('disposed entry cannot acquire a late route-complete milestone',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    final trace = ChatEntryTrace(1);
    await tester
        .pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
    unawaited(nav.currentState!.push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 480),
        pageBuilder: (_, __, ___) => ChatEntryRouteTiming(
            trace: trace, child: const Scaffold(body: Text('entry'))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    nav.currentState!.pop();
    trace.close();
    await tester.pumpAndSettle();
    expect(trace.transitionFinished, isFalse);
    expect(tester.takeException(), isNull);
  });
}
