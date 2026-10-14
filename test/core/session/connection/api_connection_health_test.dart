import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/connection/api_connection_health.dart';

void main() {
  testWidgets('repeated snapshots retain latency and do not invalidate probes',
      (tester) async {
    final network = StreamController<List<ConnectivityResult>>();
    var checks = 0;
    final health = ApiConnectionHealth(
      isCurrent: () => true,
      networkChanges: network.stream,
      check: () async {
        checks++;
        return true;
      },
    )..start();
    network.add([ConnectivityResult.wifi]);
    await tester.pump();
    final before = checks;
    final latency = health.latencyMs.value;
    network.add([ConnectivityResult.wifi]);
    network.add([]);
    await tester.pump();
    expect(checks, before);
    expect(health.available.value, true);
    expect(health.latencyMs.value, latency);
    health.close();
    unawaited(network.close());
    await tester.pump();
  });
  testWidgets(
      'offline clears latency and prevents new probes until network returns',
      (tester) async {
    final network = StreamController<List<ConnectivityResult>>();
    var checks = 0;
    final health = ApiConnectionHealth(
        isCurrent: () => true,
        networkChanges: network.stream,
        check: () async {
          checks++;
          return true;
        })
      ..start();
    await tester.pump();
    expect(health.latencyMs.value, isNotNull);
    network.add([ConnectivityResult.none]);
    await tester.pump();
    expect(health.latencyMs.value, isNull);
    expect(health.available.value, false);
    await tester.pump(const Duration(seconds: 30));
    expect(checks, 1);
    network.add([ConnectivityResult.wifi]);
    await tester.pump();
    expect(checks, 2);
    health.close();
    unawaited(network.close());
    await tester.pump();
  });
  testWidgets(
      'API failures retry in three seconds and healthy checks slow down',
      (tester) async {
    var healthy = false;
    var checks = 0;
    final health = ApiConnectionHealth(
        networkChanges: const Stream.empty(),
        isCurrent: () => true,
        check: () async {
          checks++;
          return healthy;
        })
      ..start();
    await tester.pump();
    expect(health.available.value, false);
    await tester.pump(const Duration(seconds: 2));
    expect(checks, 1);
    healthy = true;
    await tester.pump(const Duration(seconds: 1));
    expect(checks, 2);
    expect(health.available.value, true);
    expect(health.latencyMs.value, isNotNull);
    await tester.pump(const Duration(seconds: 4));
    expect(checks, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(checks, 3);
    health.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(health.latencyMs.value, isNull);
    await tester.pump(const Duration(minutes: 1));
    expect(checks, 3);
    health.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(checks, 4);
    health.close();
    await tester.pump(const Duration(minutes: 1));
    expect(checks, 4);
  });

  testWidgets('late API result cannot publish into an expired session',
      (tester) async {
    final pending = Completer<bool>();
    var current = true;
    final health = ApiConnectionHealth(
        networkChanges: const Stream.empty(),
        isCurrent: () => current,
        check: () => pending.future)
      ..start();
    current = false;
    pending.complete(true);
    await tester.pump();
    expect(health.available.value, isNull);
    health.close();
  });

  testWidgets(
      'failures back off, network recovery resets, and close unsubscribes',
      (tester) async {
    final network = StreamController<List<ConnectivityResult>>();
    var checks = 0;
    final health = ApiConnectionHealth(
      isCurrent: () => true,
      networkChanges: network.stream,
      check: () async {
        checks++;
        return false;
      },
    )..start();
    await tester.pump();
    for (final seconds in [3, 6, 12, 30, 30]) {
      final before = checks;
      await tester.pump(Duration(seconds: seconds - 1));
      expect(checks, before);
      await tester.pump(const Duration(seconds: 1));
      expect(checks, before + 1);
    }
    network.add([ConnectivityResult.wifi]);
    await tester.pump();
    expect(checks, 7);
    await tester.pump(const Duration(seconds: 3));
    expect(checks, 8);
    health.didChangeAppLifecycleState(AppLifecycleState.paused);
    network.add([ConnectivityResult.mobile]);
    await tester.pump(const Duration(minutes: 1));
    expect(checks, 8);
    health.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(checks, 9);
    await tester.pump(const Duration(seconds: 3));
    expect(checks, 10);
    health.close();
    expect(network.hasListener, isFalse);
    unawaited(network.close());
    await tester.pump();
  });
}
