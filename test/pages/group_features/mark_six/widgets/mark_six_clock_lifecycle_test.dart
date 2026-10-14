import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_controller.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_repository.dart';
import 'package:openim/pages/group_features/mark_six/models/mark_six_draw.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_latest_card.dart';
import '../mark_six_fixtures.dart';

class _ClockController extends MarkSixController {
  _ClockController()
      : super(MarkSixRepository(markSixContext(MarkSixFakeApi()))) {
    config = {};
    draws = [
      MarkSixDraw({
        'issue': '1',
        'status': 'open',
        'closeAt': DateTime.utc(2026, 1, 1, 0, 1).millisecondsSinceEpoch
      })
    ];
  }
  DateTime time = DateTime.utc(2026);
  int clockReads = 0, cardBuilds = 0;
  bool get observed => hasListeners;
  @override
  DateTime now() {
    clockReads++;
    return time;
  }

  @override
  MarkSixDraw? get latest {
    cardBuilds++;
    return super.latest;
  }
}

void main() {
  late Duration interval;
  setUp(() {
    interval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(
      () => VisibilityDetectorController.instance.updateInterval = interval);

  testWidgets(
      'offscreen clock stops and controller replacement releases listener',
      (tester) async {
    final first = _ClockController();
    final second = _ClockController()
      ..time = DateTime.utc(2026, 1, 1, 0, 0, 40);
    var current = first;
    final scroll = ScrollController();
    late StateSetter update;
    await tester
        .pumpWidget(MaterialApp(home: StatefulBuilder(builder: (_, setState) {
      update = setState;
      return Scaffold(
          body: SingleChildScrollView(
              controller: scroll,
              child: Column(children: [
                MarkSixLatestCard(controller: current, preview: true),
                const SizedBox(height: 2000),
              ])));
    })));
    await tester.pump();
    scroll.jumpTo(1000);
    await tester.pump();
    await tester.pump();
    final hidden = first.clockReads;
    await tester.pump(const Duration(seconds: 5));
    expect(first.clockReads, hidden);
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump();
    update(() => current = second);
    await tester.pump();
    await tester.pump();
    expect(first.observed, isFalse);
    expect(find.text('封盘 0:20'), findsOneWidget);
    final retired = first.clockReads;
    await tester.pump(const Duration(seconds: 1));
    expect(first.clockReads, retired);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.observed, isFalse);
    first.dispose();
    second.dispose();
    scroll.dispose();
  });

  testWidgets('visible clock ticks without rebuilding card; hidden clock stops',
      (tester) async {
    final controller = _ClockController();
    var active = true;
    late StateSetter update;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return Scaffold(
          body: TickerMode(
              enabled: active,
              child: Offstage(
                  offstage: !active,
                  child: MarkSixLatestCard(
                      controller: controller, preview: true))));
    })));
    await tester.pump();
    final builds = controller.cardBuilds;
    controller.time = controller.time.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('封盘 0:59'), findsOneWidget);
    expect(controller.cardBuilds, builds);
    update(() => active = false);
    await tester.pump();
    await tester.pump();
    final reads = controller.clockReads;
    controller.time = controller.time.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    expect(controller.clockReads, reads);
    update(() => active = true);
    await tester.pump();
    await tester.pump();
    expect(find.text('封盘 0:39'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
      'background and covered routes stop ticks; resume reads wall time',
      (tester) async {
    final controller = _ClockController();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
            body: MarkSixLatestCard(controller: controller, preview: true))));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final before = controller.clockReads;
    controller.time = controller.time.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(controller.clockReads, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('封盘 0:30'), findsOneWidget);
    nav.currentState!.push(PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => const Center(child: Text('overlay'))));
    await tester.pumpAndSettle();
    final covered = controller.clockReads;
    await tester.pump(const Duration(seconds: 5));
    expect(controller.clockReads, covered);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    final restored = controller.clockReads;
    await tester.pump(const Duration(seconds: 1));
    expect(controller.clockReads, greaterThan(restored));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
