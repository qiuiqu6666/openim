import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/startup_node_selection.dart';
import 'package:openim/core/youmeng/youmeng_runtime.dart';

void main() {
  const custom = NodeEndpoint(
      chatApi: 'https://custom.test',
      imApi: 'https://im.custom.test',
      imWs: 'wss://ws.custom.test');

  for (final enabled in [false, true]) {
    for (final available in [false, true]) {
      for (final node in [NodeEndpoint.direct, custom]) {
        test('enabled=$enabled available=$available node=${node.chatApi}',
            () async {
          final events = <String>[];
          await YoumengRuntime.prepareWithFallback(
            shieldEnabled: enabled,
            select: () async {
              events.add('probe');
              return NodeSelection(node, [
                NodeAvailability(node, available: available, latencyMs: 1),
              ]);
            },
            startShield: () async {
              events.add('shield');
            },
          );
          expect(events, [
            'probe',
            if (enabled && !available && node == NodeEndpoint.direct) 'shield',
          ]);
        });
      }
    }
  }

  test('any available built-in prevents fallback', () async {
    await YoumengRuntime.prepareWithFallback(
      shieldEnabled: true,
      select: () async => NodeSelection(NodeEndpoint.direct, [
        const NodeAvailability(NodeEndpoint.direct,
            available: false, latencyMs: 1),
        const NodeAvailability(NodeEndpoint.direct,
            available: true, latencyMs: 1),
      ]),
      startShield: () async => fail('Should not start shield'),
    );
  });

  test('shield startup failure propagates to the in-app retry owner', () async {
    await expectLater(
        YoumengRuntime.prepareWithFallback(
          shieldEnabled: true,
          select: () async => NodeSelection(NodeEndpoint.direct, [
            const NodeAvailability(NodeEndpoint.direct,
                available: false, latencyMs: 1),
          ]),
          startShield: () async => throw StateError('not ready'),
        ),
        throwsStateError);
  });
}
