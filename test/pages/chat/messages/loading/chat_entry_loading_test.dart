import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/messages/loading/chat_entry_skeleton.dart';
import 'package:openim/pages/chat/messages/loading/chat_initial_window_transition.dart';

Widget host(Widget child,
        {Brightness brightness = Brightness.light,
        bool reduceMotion = false,
        Size size = const Size(375, 640)}) =>
    ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
                body: MediaQuery(
                    data: MediaQueryData(
                        disableAnimations: reduceMotion,
                        textScaler: const TextScaler.linear(2)),
                    child: Center(
                        child: SizedBox(
                            width: size.width,
                            height: size.height,
                            child: child))))));

void main() {
  testWidgets(
      'paint timing ignores hidden content and separates reveal from interaction',
      (tester) async {
    final frames = <bool>[];
    Widget view(bool loading) => host(ChatInitialWindowTransition(
        loading: loading,
        skeleton: const Text('gray'),
        onContentPainted: frames.add,
        child: const Text('messages')));
    await tester.pumpWidget(view(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(frames, isEmpty);
    await tester.pumpWidget(view(false));
    await tester.pump();
    expect(frames, isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    expect(frames, isNotEmpty);
    expect(frames.last, isFalse);
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump();
    expect(frames.last, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    final count = frames.length;
    await tester.pump(const Duration(milliseconds: 300));
    expect(frames.length, count);
  });
  for (final brightness in Brightness.values) {
    for (final group in [false, true]) {
      testWidgets(
          'skeleton fits $brightness group=$group at large text and short height',
          (tester) async {
        for (final size in [const Size(320, 560), const Size(240, 160)]) {
          await tester.pumpWidget(host(
              ChatEntrySkeleton(
                  isGroup: group, latestOutgoing: !group, latestIsMedia: true),
              brightness: brightness,
              size: size));
          await tester.pump(const Duration(milliseconds: 450));
          expect(tester.takeException(), isNull);
          expect(find.byType(ChatEntrySkeleton), findsOneWidget);
          for (final bubble
              in tester.widgetList<ChatBubble>(find.byType(ChatBubble))) {
            expect(
                bubble.backgroundColor,
                Color.alphaBlend(
                    AppTokens.border(dark: brightness == Brightness.dark),
                    AppTokens.background(dark: brightness == Brightness.dark)),
                reason:
                    'The entire bubble is gray, including outgoing bubbles');
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('crossfade preserves the mounted list and scroll offset',
      (tester) async {
    final key = GlobalKey<ChatInitialWindowTransitionState>();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var reveals = 0;
    Widget view(bool loading) => host(ChatInitialWindowTransition(
        key: key,
        loading: loading,
        onRevealed: () => reveals++,
        skeleton: const ChatEntrySkeleton(isGroup: true),
        child: ListView.builder(
            key: const ValueKey('real-timeline'),
            controller: controller,
            itemExtent: 48,
            itemCount: 60,
            itemBuilder: (_, i) => Text('message $i'))));
    await tester.pumpWidget(view(true));
    controller.jumpTo(192);
    await tester.pump();
    final element = tester.element(find.byKey(const ValueKey('real-timeline')));
    expect(key.currentState!.canReportContent, isFalse);
    // A visible loading state retains the full, gentle 120ms reveal.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(view(false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(key.currentState!.canReportContent, isFalse);
    final opacity = tester
        .widget<FadeTransition>(find
            .descendant(
                of: find.byKey(key), matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;
    expect(opacity, greaterThan(0));
    expect(opacity, lessThan(1),
        reason: 'Real content fades in rather than snapping visible');
    expect(find.byType(ChatEntrySkeleton), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(key.currentState!.canReportContent, isTrue);
    expect(find.byType(ChatEntrySkeleton), findsNothing);
    expect(tester.element(find.byKey(const ValueKey('real-timeline'))),
        same(element));
    expect(controller.offset, 192);
    expect(reveals, 1);
    await tester.pumpWidget(view(false));
    expect(reveals, 1,
        reason: 'Ordinary message rebuilds do not replay entry motion');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('brief local load reveals in 80ms without replacing real content',
      (tester) async {
    final key = GlobalKey<ChatInitialWindowTransitionState>();
    const contentKey = ValueKey('brief-real-message');
    Widget view(bool loading) => host(ChatInitialWindowTransition(
        key: key,
        loading: loading,
        skeleton: const Text('gray'),
        child: const Text('message', key: contentKey)));
    await tester.pumpWidget(view(true));
    final element = tester.element(find.byKey(contentKey));
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pumpWidget(view(false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(key.currentState!.canReportContent, isFalse);
    final fade = tester.widget<FadeTransition>(find
        .descendant(of: find.byKey(key), matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 41));
    await tester.pump();
    expect(key.currentState!.canReportContent, isTrue);
    expect(tester.element(find.byKey(contentKey)), same(element));
    expect(find.text('gray'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'reduced motion uses a static skeleton and reveals without animation',
      (tester) async {
    final key = GlobalKey<ChatInitialWindowTransitionState>();
    Widget view(bool loading) => host(
        ChatInitialWindowTransition(
            key: key,
            loading: loading,
            skeleton: const ChatEntrySkeleton(isGroup: false),
            child: const Text('real messages')),
        reduceMotion: true);
    await tester.pumpWidget(view(true));
    await tester.pumpAndSettle();
    expect(key.currentState!.canReportContent, isFalse);
    await tester.pumpWidget(view(false));
    await tester.pump();
    expect(key.currentState!.canReportContent, isTrue);
    expect(find.byType(ChatEntrySkeleton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'retry replaces an interrupted reveal and disposal cancels deferred work',
      (tester) async {
    final key = GlobalKey<ChatInitialWindowTransitionState>();
    var reveals = 0;
    Widget view(bool loading) => host(ChatInitialWindowTransition(
        key: key,
        loading: loading,
        onRevealed: () => reveals++,
        skeleton: const ChatEntrySkeleton(isGroup: false),
        child: const Text('real messages')));
    await tester.pumpWidget(view(true));
    await tester.pumpWidget(view(false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(view(true));
    await tester.pump(const Duration(milliseconds: 260));
    expect(key.currentState!.canReportContent, isFalse);
    expect(reveals, 0);
    await tester.pumpWidget(view(false));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(reveals, 0);
  });
}
