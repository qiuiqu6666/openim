import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/loading/chat_entry_loading_hint.dart';
import 'package:openim/pages/chat/messages/loading/chat_initial_window_transition.dart';

Widget host(Widget child,
        {Brightness brightness = Brightness.light, bool reduced = false}) =>
    MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(
                    disableAnimations: reduced,
                    textScaler: const TextScaler.linear(2)),
                child: child)));

void main() {
  for (final brightness in Brightness.values) {
    for (final reduced in [false, true]) {
      testWidgets(
          '200ms hint; immediate real content $brightness reduced=$reduced',
          (tester) async {
        final key = GlobalKey<ChatInitialWindowTransitionState>();
        final frames = <bool>[];
        var taps = 0;
        Widget view(bool loading) => host(
            ChatInitialWindowTransition(
                key: key,
                loading: loading,
                loadingIndicator: const ChatEntryLoadingHint(),
                onContentPainted: frames.add,
                child: TextButton(
                    onPressed: () => taps++, child: const Text('message'))),
            brightness: brightness,
            reduced: reduced);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(view(true));
        await tester.pump(const Duration(milliseconds: 199));
        expect(find.byType(ChatEntryLoadingHint), findsNothing);
        expect(frames, isEmpty);
        expect(key.currentState!.canReportContent, isFalse);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.byType(ChatEntryLoadingHint), findsOneWidget);
        expect(find.byType(ShaderMask), findsNothing);
        await tester.pumpWidget(view(false));
        expect(key.currentState!.canReportContent, isTrue);
        expect(find.byType(ChatEntryLoadingHint), findsNothing);
        expect(frames.last, isTrue);
        await tester.tap(find.text('message'));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('fast load never flashes hint and retains scroll state',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final key = GlobalKey<ChatInitialWindowTransitionState>();
    var reveals = 0;
    Widget view(bool loading) => host(ChatInitialWindowTransition(
        key: key,
        loading: loading,
        onRevealed: () => reveals++,
        loadingIndicator: const ChatEntryLoadingHint(),
        child: ListView.builder(
            key: const ValueKey('list'),
            controller: controller,
            itemExtent: 48,
            itemCount: 60,
            itemBuilder: (_, i) => Text('$i'))));
    await tester.pumpWidget(view(true));
    controller.jumpTo(192);
    await tester.pump(const Duration(milliseconds: 32));
    final element = tester.element(find.byKey(const ValueKey('list')));
    await tester.pumpWidget(view(false));
    expect(key.currentState!.canReportContent, isTrue);
    expect(controller.offset, 192);
    expect(tester.element(find.byKey(const ValueKey('list'))), same(element));
    expect(reveals, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatEntryLoadingHint), findsNothing);
    await tester.pumpWidget(view(false));
    expect(reveals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retry gets a fresh delay; disposal cancels pending timer',
      (tester) async {
    Widget view(bool loading) => host(ChatInitialWindowTransition(
        loading: loading,
        loadingIndicator: const ChatEntryLoadingHint(),
        child: const Text('message')));
    await tester.pumpWidget(view(true));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpWidget(view(false));
    await tester.pumpWidget(view(true));
    await tester.pump(const Duration(milliseconds: 199));
    expect(find.byType(ChatEntryLoadingHint), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ChatEntryLoadingHint), findsOneWidget);
    await tester.pumpWidget(view(false));
    await tester.pumpWidget(view(true));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
