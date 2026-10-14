import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/timed_node_probe.dart';

void main() {
  for (final available in [NodeEndpoint.direct, NodeEndpoint.backup, null]) {
    test('cumulative deadlines for ${available?.chatApi}', () {
      fakeAsync((clock) {
        List<NodeAvailability>? results;
        final probed = <NodeEndpoint>[];
        TimedNodeProbe(probe: (node) async {
          probed.add(node);
          return NodeAvailability(node,
              available: node == available, latencyMs: 1);
        }).check(NodeEndpoint.builtIn).then((value) => results = value);
        clock.flushMicrotasks();
        expect(probed, NodeEndpoint.builtIn);
        final milliseconds = available == NodeEndpoint.direct
            ? 1000
            : available == NodeEndpoint.backup
                ? 1250
                : 2250;
        clock.elapse(Duration(milliseconds: milliseconds - 1));
        expect(results, isNull);
        clock.elapse(const Duration(milliseconds: 1));
        expect(results, isNotNull);
        expect(results!.where((value) => value.available).length,
            available == null ? 0 : 1);
      });
    });
  }
  test('hanging probes do not block fallback; late results cannot mutate it',
      () {
    fakeAsync((clock) {
      final gate = Completer<NodeAvailability>();
      List<NodeAvailability>? results;
      TimedNodeProbe(probe: (_) => gate.future)
          .check([NodeEndpoint.direct]).then((value) => results = value);
      clock.elapse(const Duration(milliseconds: 2250));
      expect(results!.single.available, isFalse);
      gate.complete(const NodeAvailability(NodeEndpoint.direct,
          available: true, latencyMs: 3000));
      clock.flushMicrotasks();
      expect(results!.single.available, isFalse);
    });
  });
}
