import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_controller.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_repository.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_latest_card.dart';

import '../../pages/group_features/mark_six/mark_six_fixtures.dart';
import '../../pages/customer_service/customer_service_test_fakes.dart';

// Visibility is a regression contract; timings are host/JIT observations,
// not phone FPS or a timing-sensitive CI gate.
void main() {
  testWidgets('regression: offstage latest card performs no periodic work',
      (tester) async {
    final controller = _CountingMarkSixController()..loading = true;
    await tester.pumpWidget(MaterialApp(
      home: TickerMode(
        enabled: false,
        child: Offstage(
          offstage: true,
          child: MarkSixLatestCard(controller: controller),
        ),
      ),
    ));
    final before = controller.currentReads;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final reads = controller.currentReads - before;
    // No timer callback or widget build while hidden.
    expect(reads, 0);
    // ignore: avoid_print
    print('AUDIT offstage_card seconds=5 timer_checks=0 hidden_rebuilds=0');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('audit: customer service history merge scaling', () async {
    for (final size in [100, 1000, 5000]) {
      final harness = CustomerServiceTestHarness();
      harness.api.history = List.generate(
          size,
          (i) => customerServiceTestMessage('$i', 'audit message $i',
              createdAt: DateTime.utc(2026).add(Duration(seconds: i))));
      final timer = Stopwatch()..start();
      await harness.controller.initialize();
      final initialMicros = timer.elapsedMicroseconds;
      harness.api.history = List.generate(
          size,
          (i) => customerServiceTestMessage('$i', 'audit message $i',
              createdAt: DateTime.utc(2026).add(Duration(seconds: i))));
      timer.reset();
      await harness.controller.refresh();
      final refreshMicros = timer.elapsedMicroseconds;
      timer.stop();
      expect(harness.controller.entries.length, size);
      // ignore: avoid_print
      print('AUDIT customer_service rows=$size initial_us=$initialMicros '
          'unchanged_refresh_us=$refreshMicros');
      harness.dispose();
    }
  });
}

class _CountingMarkSixController extends MarkSixController {
  _CountingMarkSixController()
      : super(MarkSixRepository(markSixContext(MarkSixFakeApi())));
  int currentReads = 0;
  @override
  bool get current {
    currentReads++;
    return super.current;
  }
}
