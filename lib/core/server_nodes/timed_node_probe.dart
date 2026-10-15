import 'dart:async';

import 'node_availability_probe.dart';
import 'node_endpoint.dart';

/// Parallel, credential-free probes with cumulative decision deadlines.
class TimedNodeProbe {
  TimedNodeProbe(
      {Future<NodeAvailability> Function(NodeEndpoint)? probe,
      this.cancelPending})
      : _probe = probe;

  final Future<NodeAvailability> Function(NodeEndpoint)? _probe;
  final void Function()? cancelPending;
  final _availability =
      NodeAvailabilityProbe(timeout: const Duration(milliseconds: 2250));

  Future<List<NodeAvailability>> check(List<NodeEndpoint> nodes) async {
    if (nodes.isEmpty) return [];
    final results = <NodeEndpoint, NodeAvailability>{};
    for (final node in nodes) {
      unawaited(Future.sync(() => (_probe ?? _availability.check)(node)).then(
          (value) {
        results[node] = value;
      }, onError: (Object _) {
        results[node] = NodeAvailability(node, available: false, latencyMs: 0);
      }));
    }
    // At 1 s only the preferred route wins. From 1.25 s any verified route
    // wins. At 2.25 s unresolved requests count as unavailable this round.
    for (final delay in [1000, 250, 1000]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (delay == 250 && results.values.any((value) => value.available)) break;
      if (results[nodes.first]?.available == true) break;
    }
    _availability.cancel();
    cancelPending?.call();
    return [
      for (final node in nodes)
        results[node] ??
            NodeAvailability(node, available: false, latencyMs: 2250)
    ];
  }
}
