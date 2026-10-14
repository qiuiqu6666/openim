import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/youmeng/youmeng_runtime.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/startup_node_selection.dart';

void main() {
  NodeSelection direct(bool available) => NodeSelection(NodeEndpoint.direct, [
        NodeAvailability(NodeEndpoint.direct,
            available: available, latencyMs: 1)
      ]);
  test('shield starts immediately and launch does not wait for blocked direct',
      () async {
    final probe = Completer<NodeSelection>();
    final events = <String>[];
    await YoumengRuntime.prepareRememberedShield(
      startShield: () async {
        events.add('shield');
      },
      checkDirect: () {
        events.add('probe');
        return probe.future;
      },
      applyDirect: (_) async => fail('A late probe must not change the route'),
    );
    expect(events, ['shield', 'probe']);
    probe.complete(direct(true));
    await Future<void>.delayed(Duration.zero);
  });
  test('failed shield uses verified direct fallback', () async {
    NodeEndpoint? applied;
    await YoumengRuntime.prepareRememberedShield(
      startShield: () async => throw StateError('offline'),
      checkDirect: () async => direct(true),
      applyDirect: (node) async {
        applied = node;
      },
    );
    expect(applied, NodeEndpoint.direct);
  });
  test('both failing propagate to existing automatic startup retry', () async {
    await expectLater(
        YoumengRuntime.prepareRememberedShield(
          startShield: () async => throw StateError('offline'),
          checkDirect: () async => direct(false),
          applyDirect: (_) async => fail('Cannot apply unhealthy direct'),
        ),
        throwsStateError);
  });
}
