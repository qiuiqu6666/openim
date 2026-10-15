import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/connection/im_connection_recovery.dart';

void main() {
  testWidgets('recovered sync invalidates a queued failure verification',
      (tester) async {
    final signals = StreamController<void>();
    var failed = false, wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      isSyncFailed: () => failed,
      networkChanges: const Stream.empty(),
      syncRecoverySignals: signals.stream,
      wake: (_) async => wakes++,
      onError: (error) => fail('$error'),
    )..start();
    addTearDown(recovery.close);
    failed = true;
    signals.add(null);
    await tester.pump();
    failed = false;
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(wakes, 0);
    recovery.close();
    unawaited(signals.close());
    await tester.pump();
  });
}
