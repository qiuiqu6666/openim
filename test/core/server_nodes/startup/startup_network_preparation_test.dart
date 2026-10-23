import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/startup/startup_network_preparation.dart';
import 'package:openim/core/server_nodes/startup/startup_state.dart';
import 'package:openim/core/server_nodes/startup/startup_trace.dart';

class Request {
  Request(this.node, this.generation, this.report);
  final NodeEndpoint node;
  final int generation;
  final void Function(StartupHealth) report;
  final done = Completer<void>();
  void result(
      {bool chat = true, bool api = true, String ws = 'ok', DateTime? at}) {
    report(StartupHealth(
        node,
        generation,
        {
          'chat': chat ? 'ok' : 'timeout',
          'imApi': api ? 'ok' : 'timeout',
          'imWs': ws
        },
        checkedAt: at));
    if (!done.isCompleted) done.complete();
  }
}

class Harness {
  Harness({bool shield = false, NodeEndpoint current = NodeEndpoint.direct}) {
    service = StartupNetworkPreparation(
        shieldEnabled: shield,
        networkChanges: network.stream,
        networkSnapshot: () async => [],
        readCurrent: () => current,
        install: installed.add,
        trace: StartupTrace(sink: logs.add),
        jitter: () => 1,
        prepareShield: () {
          shieldStarts++;
          return native.future;
        },
        cancelShield: () async {},
        probe: (node, generation, callback) {
          final request = Request(node, generation, callback);
          requests.add(request);
          return request.done.future;
        });
  }
  late final StartupNetworkPreparation service;
  final network =
      StreamController<List<ConnectivityResult>>.broadcast(sync: true);
  final requests = <Request>[];
  final installed = <NodeEndpoint>[];
  final logs = <String>[];
  final native = Completer<void>();
  int shieldStarts = 0;
  Future<void> close(WidgetTester tester) async {
    service.onClose();
    if (!native.isCompleted) native.complete();
    for (final r in requests) {
      if (!r.done.isCompleted) r.done.complete();
    }
    await network.close();
    await tester.pump();
  }
}

void main() {
  testWidgets(
      'remembered shield falls back to direct without native completion',
      (tester) async {
    final h = Harness(shield: true, current: NodeEndpoint.shield);
    unawaited(h.service.prepare());
    expect(h.requests.map((r) => r.node), containsAll(NodeEndpoint.builtIn));
    expect(h.shieldStarts, 1);
    h.requests.first.result();
    await tester.pump();
    expect(h.installed, [NodeEndpoint.direct]);
    await h.close(tester);
  });

  testWidgets('login recovery wakes on network return and serializes retries',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    h.requests.first.result();
    await tester.pump();
    final gate = Completer<void>();
    var calls = 0;
    h.service.loginFailed(() async {
      calls++;
      await gate.future;
    });
    h.network.add([ConnectivityResult.none]);
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 0);
    h.network.add([ConnectivityResult.mobile]);
    await tester.pump();
    expect(calls, 1);
    h.network.add([ConnectivityResult.wifi]);
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 1);
    gate.complete();
    await tester.pump();
    h.service.finishHandoff('home');
    expect(h.service.loginRecoveryVisible, isFalse);
    h.network.add([ConnectivityResult.mobile]);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    await h.close(tester);
  });

  testWidgets('unavailable copy remains stable through background probing',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    for (var i = 0; i < 3; i++) {
      for (final r in h.requests.where((r) => !r.done.isCompleted).toList()) {
        r.result(chat: false);
      }
      await tester.pump();
      if (i < 2) await tester.pump(const Duration(seconds: 1));
    }
    expect(h.service.state.value.stage, StartupStage.unavailable);
    await tester.pump(const Duration(seconds: 3));
    expect(h.service.state.value.stage, StartupStage.unavailable);
    await h.close(tester);
  });
  testWidgets(
      'SDK failure exposes recovery without reopening route selection or concurrent init',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    h.requests.first.result();
    await tester.pump();
    final gate = Completer<void>();
    var inits = 0;
    h.service.sdkFailed(() {
      inits++;
      return gate.future;
    });
    expect(h.service.state.value.stage, StartupStage.unavailable);
    expect(h.service.state.value.showActions, isTrue);
    h.service.retry();
    h.service.retry();
    expect(inits, 1);
    expect(h.installed.length, 1);
    gate.complete();
    await tester.pump();
    h.service.finishHandoff('home');
    expect(h.service.sdkRecoveryVisible, isFalse);
    await h.close(tester);
  });
  setUp(() => PackageInfo.setMockInitialValues(
      appName: '99Chat',
      packageName: 'test',
      version: '3.0.1',
      buildNumber: '2036',
      buildSignature: ''));
  testWidgets(
      'healthy direct releases once while shield hangs; late shield cannot change route',
      (tester) async {
    final h = Harness(shield: true);
    var starts = 0;
    final pending = h.service.prepare();
    expect(h.service.prepare(), same(pending));
    unawaited(pending.then((_) => starts++));
    expect(h.shieldStarts, 1);
    h.requests.first.result();
    await tester.pump();
    expect(starts, 1);
    expect(h.service.state.value.stage, StartupStage.ready);
    h.native.complete();
    await tester.pump();
    h.requests.last.result();
    await tester.pump();
    expect(h.installed.single.signature, NodeEndpoint.direct.signature);
    await h.close(tester);
  });

  testWidgets('native failure cannot delay healthy direct', (tester) async {
    final h = Harness(shield: true);
    unawaited(h.service.prepare());
    h.native.completeError(StateError('failed'));
    h.requests[1].result();
    await tester.pump();
    expect(h.installed, [NodeEndpoint.backup]);
    await h.close(tester);
  });

  testWidgets('shield can win when direct fails', (tester) async {
    final h = Harness(shield: true);
    unawaited(h.service.prepare());
    for (final r in h.requests.toList()) {
      r.result(chat: false);
    }
    h.native.complete();
    await tester.pump();
    h.requests.last.result();
    await tester.pump();
    expect(h.installed, [NodeEndpoint.shield]);
    await h.close(tester);
  });

  testWidgets(
      'API readiness releases degraded without claiming gateway connected',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    h.requests.first.result(ws: 'pending');
    await tester.pump();
    expect(h.service.ready, isTrue);
    expect(h.service.state.value.stage, StartupStage.degraded);
    expect(h.service.state.value.health!.fullyHealthy, isFalse);
    expect(h.service.handoffComplete, isFalse);
    h.service.finishHandoff('home');
    expect(h.service.handoffComplete, isTrue);
    await h.close(tester);
  });

  testWidgets('business API alone and stale samples never release',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    h.requests.first.result(api: false);
    h.requests[1]
        .result(at: DateTime.now().subtract(const Duration(minutes: 1)));
    await tester.pump();
    expect(h.service.ready, isFalse);
    expect(h.installed, isEmpty);
    await h.close(tester);
  });

  testWidgets(
      'first timeout recovers during quick retry without waiting for shield',
      (tester) async {
    final h = Harness(shield: true);
    unawaited(h.service.prepare());
    for (final r in h.requests.toList()) {
      r.result(chat: false);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.requests.length, 4);
    expect(h.shieldStarts, 1);
    h.requests[2].result();
    await tester.pump();
    expect(h.service.ready, isTrue);
    await h.close(tester);
  });

  testWidgets(
      'wifi to mobile invalidates old callbacks and commits new generation',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    h.network.add([ConnectivityResult.wifi]);
    await tester.pump();
    final old = h.requests.last;
    h.network.add([ConnectivityResult.mobile]);
    await tester.pump();
    old.result();
    await tester.pump();
    expect(h.installed, isEmpty);
    h.requests.last.result();
    await tester.pump();
    expect(h.installed, [NodeEndpoint.backup]);
    await h.close(tester);
  });

  testWidgets('offline to online retries immediately even during backoff',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    h.network.add([ConnectivityResult.none]);
    await tester.pump();
    expect(h.service.state.value.stage, StartupStage.unavailable);
    final count = h.requests.length;
    h.network.add([ConnectivityResult.mobile]);
    await tester.pump();
    expect(h.requests.length, count + 2);
    h.requests.last.result();
    await tester.pump();
    expect(h.service.ready, isTrue);
    await h.close(tester);
  });

  testWidgets(
      'background invalidates probes; resume checks fresh; success never reopens startup',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    final old = h.requests.first;
    h.service.didChangeAppLifecycleState(AppLifecycleState.paused);
    old.result();
    await tester.pump();
    expect(h.installed, isEmpty);
    h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    h.requests.last.result();
    await tester.pump();
    final count = h.requests.length;
    h.service.didChangeAppLifecycleState(AppLifecycleState.paused);
    h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    h.service.retry();
    await tester.pump(const Duration(minutes: 1));
    expect(h.requests.length, count);
    expect(h.installed.length, 1);
    await h.close(tester);
  });

  testWidgets('simultaneous successes commit exactly once', (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    h.requests[1].result();
    h.requests[0].result();
    await tester.pump();
    expect(h.installed, [NodeEndpoint.backup]);
    await h.close(tester);
  });

  testWidgets(
      'persistent failure exposes actions and bounded exponential retries',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    for (var i = 0; i < 8; i++) {
      for (final r in h.requests.where((r) => !r.done.isCompleted).toList()) {
        r.result(chat: false);
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
    }
    expect(h.service.state.value.showActions, isTrue);
    expect(h.service.state.value.showDetails, isTrue);
    expect(h.service.ready, isFalse);
    expect(h.requests.length, lessThanOrEqualTo(18));
    expect(h.logs.any((l) => l.contains('30000')), isTrue);
    await h.close(tester);
  });

  testWidgets('automatic retry invalidates previous probing round',
      (tester) async {
    final h = Harness();
    unawaited(h.service.prepare());
    final old = h.requests.first;
    h.service.retry();
    old.result();
    await tester.pump();
    expect(h.installed, isEmpty);
    h.requests.last.result();
    await tester.pump();
    expect(h.installed.single.signature, NodeEndpoint.backup.signature);
    await h.close(tester);
  });

  for (final phase in ['SDK initialization', 'login']) {
    testWidgets('network change during $phase cannot mutate committed route',
        (tester) async {
      final h = Harness();
      unawaited(h.service.prepare());
      h.requests.first.result();
      await tester.pump();
      expect(h.service.handoffComplete, isFalse);
      h.network.add([ConnectivityResult.mobile]);
      h.requests[1].result();
      await tester.pump();
      expect(h.installed, [NodeEndpoint.direct]);
      h.service.finishHandoff('home');
      expect(h.service.handoffComplete, isTrue);
      await h.close(tester);
    });
  }

  testWidgets('native failure causes fresh direct probes', (tester) async {
    final h = Harness(shield: true);
    unawaited(h.service.prepare());
    for (final r in h.requests.toList()) {
      r.result(chat: false);
    }
    await tester.pump();
    h.native.completeError(StateError('failed'));
    await tester.pump();
    expect(h.requests.length, greaterThanOrEqualTo(4));
    h.requests.last.result();
    await tester.pump();
    expect(h.service.ready, isTrue);
    await h.close(tester);
  });
}
