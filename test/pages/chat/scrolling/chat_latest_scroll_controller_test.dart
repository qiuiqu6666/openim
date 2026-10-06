import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/scrolling/chat_latest_scroll_controller.dart';

class _ObservedScrollController extends ScrollController {
  final jumpDistances = <double>[];

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _ObservedScrollPosition(
          physics: physics,
          context: context,
          oldPosition: oldPosition,
          onJump: jumpDistances.add);
}

class _ObservedScrollPosition extends ScrollPositionWithSingleContext {
  _ObservedScrollPosition(
      {required super.physics,
      required super.context,
      super.oldPosition,
      required this.onJump});
  final void Function(double) onJump;

  @override
  void jumpTo(double value) {
    onJump((value - pixels).abs());
    super.jumpTo(value);
  }
}

Future<ChatLatestScrollController> _mount(
  WidgetTester tester,
  ScrollController scroll,
  VoidCallback onReachedLatest,
) async {
  final latest = ChatLatestScrollController(
    controller: scroll,
    isClosed: () => false,
    shouldFollow: () => true,
    onReachedLatest: onReachedLatest,
  );
  await tester.pumpWidget(MaterialApp(
    home: ListView.builder(
      controller: scroll,
      reverse: true,
      itemExtent: 48,
      itemCount: 100,
      itemBuilder: (_, index) => Text('$index'),
    ),
  ));
  scroll.jumpTo(900);
  await tester.pump();
  addTearDown(() async {
    latest.close();
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });
  return latest;
}

void main() {
  testWidgets('reduced motion returns immediately without an animation',
      (tester) async {
    final scroll = ScrollController();
    var reached = 0;
    final latest = await _mount(tester, scroll, () => reached++);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    latest.request(animated: true);
    await tester.pump();
    expect(scroll.offset, scroll.position.minScrollExtent);
    expect(reached, 1);
    await tester.pumpAndSettle();
    expect(reached, 1);
  });

  testWidgets('closing during a smooth return rejects its late completion',
      (tester) async {
    final scroll = ScrollController();
    var reached = 0;
    final latest = await _mount(tester, scroll, () => reached++);
    latest.request(animated: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(scroll.offset, inExclusiveRange(0, 900));
    latest.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(reached, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an explicit jump overrides smooth return without double completion',
      (tester) async {
    final scroll = ScrollController();
    var reached = 0;
    final latest = await _mount(tester, scroll, () => reached++);
    latest.request(animated: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(scroll.offset, inExclusiveRange(0, 900));
    latest.request();
    await tester.pumpAndSettle();
    expect(scroll.offset, scroll.position.minScrollExtent);
    expect(reached, 1);
  });

  testWidgets('a moving painted latest edge never ends in a large forced jump',
      (tester) async {
    final scroll = _ObservedScrollController();
    final newerCount = ValueNotifier<int>(0);
    var reached = 0;
    final latest = ChatLatestScrollController(
        controller: scroll,
        isClosed: () => false,
        shouldFollow: () => true,
        onReachedLatest: () => reached++);
    const historyKey = ValueKey('stable-history-sliver');
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<int>(
            valueListenable: newerCount,
            builder: (_, count, __) => CustomScrollView(
                  controller: scroll,
                  reverse: true,
                  center: historyKey,
                  slivers: [
                    SliverFixedExtentList(
                        itemExtent: 240,
                        delegate: SliverChildBuilderDelegate(
                            (_, index) => Text('new-$index'),
                            childCount: count)),
                    SliverFixedExtentList(
                        key: historyKey,
                        itemExtent: 48,
                        delegate: SliverChildBuilderDelegate(
                            (_, index) => Text('history-$index'),
                            childCount: 100)),
                  ],
                ))));
    addTearDown(() async {
      latest.close();
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      newerCount.dispose();
    });
    scroll.jumpTo(900);
    await tester.pump();
    scroll.jumpDistances.clear();
    final originalMinimum = scroll.position.minScrollExtent;
    latest.request(animated: true);
    await tester.pump();
    await tester.pump();
    // New rows continually refine the real before-center sliver boundary.
    // Observe behavior without reproducing the curve or correction limit.
    for (var arrival = 0; arrival < 12; arrival++) {
      newerCount.value += 2;
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(scroll.position.minScrollExtent, lessThan(originalMinimum));
    expect(scroll.offset - scroll.position.minScrollExtent, greaterThan(1));
    expect(scroll.jumpDistances, everyElement(lessThanOrEqualTo(1)));
    expect(reached, 0,
        reason: 'A newer unseen edge cannot be declared reached after a jump.');
    expect(tester.takeException(), isNull);
  });
}
