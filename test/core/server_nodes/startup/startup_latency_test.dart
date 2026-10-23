import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/timed_node_probe.dart';
import 'package:openim/core/server_nodes/startup/startup_route_probe.dart';

/// Opt-in, credential-free public health requests. Does not log in or install a route.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('compare old decision floor with parallel API release on this host',
      () async {
    // This explicitly opted-in benchmark uses real public health requests.
    final previousOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverride);
    PackageInfo.setMockInitialValues(
        appName: 'benchmark',
        packageName: 'benchmark',
        version: 'diagnostic',
        buildNumber: '0',
        buildSignature: '');
    final old = <int>[], current = <int>[];
    for (var i = 0; i < 20; i++) {
      final watch = Stopwatch()..start();
      final checks = await TimedNodeProbe().check(NodeEndpoint.builtIn);
      expect(checks.any((c) => c.available), isTrue);
      old.add(watch.elapsedMilliseconds);
      final probe = StartupRouteProbe();
      final winner = Completer<void>();
      watch.reset();
      final requests = NodeEndpoint.builtIn
          .map((node) => probe.check(node, i, (health) {
                if (health.apiReady && !winner.isCompleted) winner.complete();
              }))
          .toList();
      await winner.future.timeout(const Duration(seconds: 3));
      current.add(watch.elapsedMilliseconds);
      probe.cancel();
      await Future.wait(requests);
    }
    old.sort();
    current.sort();
    // Nearest-rank percentiles, same host and route pairs, alternating runs.
    // ignore: avoid_print
    print(jsonEncode({
      'samples': 20,
      'oldP50Ms': old[9],
      'oldP95Ms': old[18],
      'newP50Ms': current[9],
      'newP95Ms': current[18],
      'oldMs': old,
      'newMs': current
    }));
  },
      skip: !const bool.fromEnvironment('STARTUP_LIVE_PROBE'),
      timeout: const Timeout(Duration(minutes: 2)));
}
