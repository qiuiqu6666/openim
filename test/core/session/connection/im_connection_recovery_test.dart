import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/connection/im_connection_recovery.dart';

void main() {
  testWidgets('route catch-up starts immediately and retries a failed wake',
      (tester) async {
    var wakes = 0;
    var reconciliations = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      wake: (_) async {
        if (++wakes == 1) throw StateError('temporary sync failure');
      },
      onError: (_) {},
      onWakeSucceeded: () => reconciliations++,
      networkChanges: const Stream.empty(),
    )..start();
    await recovery.recoverNow();
    expect(wakes, 1);
    expect(reconciliations, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 2);
    expect(reconciliations, 1);
    recovery.close();
  });

  testWidgets('route catch-up cannot reconcile a successor session',
      (tester) async {
    var current = true;
    var reconciliations = 0;
    final pending = Completer<void>();
    final recovery = IMConnectionRecovery(
      isCurrent: () => current,
      isDisconnected: () => false,
      wake: (_) => pending.future,
      onError: (error) => fail('$error'),
      onWakeSucceeded: () => reconciliations++,
      networkChanges: const Stream.empty(),
    )..start();
    final catchUp = recovery.recoverNow();
    current = false;
    pending.complete();
    await catchUp;
    expect(reconciliations, 0);
    recovery.close();
  });

  testWidgets(
      'sync signals coalesce and stop in background or expired sessions',
      (tester) async {
    final signals = StreamController<void>();
    var current = true;
    var wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => current,
      isDisconnected: () => false,
      wake: (_) async => wakes++,
      onError: (error) => fail('$error'),
      networkChanges: const Stream.empty(),
      syncRecoverySignals: signals.stream,
    )..start();
    signals.add(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    signals.add(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(wakes, 1, reason: 'Duplicate signals cannot postpone recovery.');
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    signals.add(null);
    await tester.pump(const Duration(minutes: 2));
    expect(wakes, 1);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(wakes, 2);
    current = false;
    signals.add(null);
    await tester.pump(const Duration(minutes: 2));
    expect(wakes, 2);
    recovery.close();
    expect(signals.hasListener, isFalse);
    current = true;
    signals.add(null);
    await tester.pump(const Duration(minutes: 2));
    expect(wakes, 2);
    unawaited(signals.close());
    await tester.pump();
  });

  testWidgets('a pre-background wake cannot postpone the new foreground check',
      (tester) async {
    final stalled = Completer<void>();
    final attempts = <bool Function()>[];
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      wake: (current) {
        attempts.add(current);
        return attempts.length == 1 ? stalled.future : Future.value();
      },
      onError: (error) => fail('$error'),
      networkChanges: const Stream.empty(),
    )..start();
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(attempts, hasLength(1));
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(attempts, hasLength(2));
    expect(attempts.first(), isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(attempts, hasLength(3));
    stalled.completeError(StateError('obsolete native response'));
    await tester.pump();
    recovery.close();
  });

  testWidgets(
      'a stale connected state still gets checked after a long background',
      (tester) async {
    var wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      wake: (_) async {
        wakes++;
      },
      onError: (error) => fail('$error'),
      networkChanges: const Stream.empty(),
    )..start();
    addTearDown(recovery.close);
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 8));
    expect(wakes, 0);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(wakes, 1);
    // No connecting/failed callback arrives; the old connected flag is stale.
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 2);
    await tester.pump(const Duration(minutes: 1));
    expect(wakes, 2);
    recovery.close();
  });

  testWidgets('a missing native callback cannot permanently lock recovery',
      (tester) async {
    final stalled = Completer<void>();
    final errors = <Object>[];
    var wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => true,
      wake: (_) => ++wakes == 1 ? stalled.future : Future.value(),
      onError: errors.add,
      networkChanges: const Stream.empty(),
    )..start();
    addTearDown(recovery.close);
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 18));
    expect(errors, [isA<TimeoutException>()]);
    final wakesAtTimeout = wakes;
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, wakesAtTimeout + 1);
    final wakesAfterRetry = wakes;
    stalled.completeError(StateError('late native failure'));
    await tester.pump();
    expect(errors, hasLength(1));
    recovery.close();
    await tester.pump(const Duration(minutes: 2));
    expect(wakes, wakesAfterRetry);
  });

  testWidgets('retries disconnected sessions and slows checks once connected',
      (tester) async {
    final network = StreamController<List<ConnectivityResult>>();
    var disconnected = true;
    var wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => disconnected,
      wake: (_) async {
        wakes++;
      },
      onError: (error) => fail('$error'),
      networkChanges: network.stream,
    )..start();
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 2);
    disconnected = false;
    await tester.pump(const Duration(seconds: 30));
    expect(wakes, 2);
    await tester.pump(const Duration(minutes: 1));
    expect(wakes, 2);
    recovery.close();
    unawaited(network.close());
    await tester.pump();
  });

  testWidgets('foreground and network recovery wake; background and exit stop',
      (tester) async {
    final network = StreamController<List<ConnectivityResult>>();
    var current = true;
    var wakes = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => current,
      isDisconnected: () => true,
      wake: (_) async {
        wakes++;
      },
      onError: (error) => fail('$error'),
      networkChanges: network.stream,
    )..start();
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    network.add([ConnectivityResult.wifi]);
    await tester.pump(const Duration(seconds: 30));
    expect(wakes, 0);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(wakes, 1);
    network.add([ConnectivityResult.none]);
    await tester.pump();
    expect(wakes, 1);
    network.add([ConnectivityResult.mobile]);
    await tester.pump();
    expect(wakes, 2);
    current = false;
    network.add([ConnectivityResult.wifi]);
    await tester.pump(const Duration(seconds: 30));
    expect(wakes, 2);
    recovery.close();
    current = true;
    network.add([ConnectivityResult.mobile]);
    await tester.pump(const Duration(seconds: 30));
    expect(wakes, 2);
    unawaited(network.close());
    await tester.pump();
  });

  testWidgets('coalesces in-flight wakes and retries after native error',
      (tester) async {
    final network = StreamController<List<ConnectivityResult>>();
    final pending = Completer<void>();
    var wakes = 0;
    final errors = <Object>[];
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => true,
      wake: (_) {
        wakes++;
        return wakes == 1 ? pending.future : Future.value();
      },
      onError: errors.add,
      networkChanges: network.stream,
      wakeTimeout: const Duration(seconds: 30),
    )..start();
    network.add([ConnectivityResult.wifi]);
    await tester.pump();
    network.add([ConnectivityResult.mobile]);
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 1);
    pending.completeError(StateError('offline'));
    await tester.pump();
    expect(errors, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    expect(wakes, 2);
    recovery.close();
    unawaited(network.close());
    await tester.pump();
  });
}
