import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/connection/im_connection_recovery.dart';

void main() {
  testWidgets('persistent sync failure backs off despite repeated signals',
      (tester) async {
    final signals = StreamController<void>();
    var wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      isSyncFailed: () => true,
      networkChanges: const Stream.empty(),
      syncRecoverySignals: signals.stream,
      wake: (_) async => wakes++,
      onError: (error) => fail('$error'),
    )..start();
    addTearDown(recovery.close);
    await recovery.recoverNow();
    expect(wakes, 1);
    for (final seconds in [3, 6, 12, 24, 30, 30]) {
      for (var elapsed = 0; elapsed < seconds - 1; elapsed++) {
        signals.add(null);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }
      final before = wakes;
      await tester.pump(const Duration(seconds: 1));
      expect(wakes, before + 1);
    }
    expect(wakes, 7);
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 1));
    expect(wakes, 7);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(wakes, 8);
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 9, reason: 'A new foreground attempt resets the backoff.');
    recovery.close();
    unawaited(signals.close());
    await tester.pump();
  });

  testWidgets('native failures back off and a healthy result resets retries',
      (tester) async {
    var wakes = 0;
    var failWake = true;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      networkChanges: const Stream.empty(),
      wake: (_) async {
        wakes++;
        if (failWake) throw StateError('temporary');
      },
      onError: (_) {},
    )..start();
    addTearDown(recovery.close);
    await recovery.recoverNow();
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 2);
    failWake = false;
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 3);
    await tester.pump(const Duration(minutes: 1));
    expect(wakes, 3);
    failWake = true;
    await recovery.recoverNow();
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 5);
    recovery.close();
  });

  testWidgets('foreground ACK during sync does not reset failure backoff',
      (tester) async {
    final signals = StreamController<void>();
    var syncing = false;
    var failed = true;
    var wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      isSyncFailed: () => failed,
      isSyncing: () => syncing,
      networkChanges: const Stream.empty(),
      syncRecoverySignals: signals.stream,
      wake: (_) async {
        wakes++;
        syncing = true;
        failed = false;
      },
      onError: (error) => fail('$error'),
    )..start();
    await recovery.recoverNow();
    for (final seconds in [3, 6, 12]) {
      syncing = false;
      failed = true;
      signals.add(null);
      await tester.pump();
      final before = wakes;
      await tester.pump(Duration(seconds: seconds - 1));
      expect(wakes, before);
      await tester.pump(const Duration(seconds: 1));
      expect(wakes, before + 1);
    }
    recovery.close();
    unawaited(signals.close());
    await tester.pump();
  });
}
