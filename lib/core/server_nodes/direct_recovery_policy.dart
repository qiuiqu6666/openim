import 'node_availability_probe.dart';
import 'node_endpoint.dart';

/// Requires sustained recovery on the same direct route before leaving shield.
class DirectRecoveryPolicy {
  final _successes = <String, int>{};
  DateTime? _lastSample, _retryAfter;

  void reset() {
    _successes.clear();
    _lastSample = null;
  }

  void failed(DateTime now) {
    reset();
    _retryAfter = now.add(const Duration(minutes: 10));
  }

  NodeEndpoint? observe(List<NodeAvailability> checks, DateTime now) {
    if (_retryAfter != null && now.isBefore(_retryAfter!)) return null;
    // SDK callbacks may trigger multiple checks in one second. They must not
    // turn three quick responses into evidence of sustained recovery.
    for (final node in NodeEndpoint.builtIn) {
      if (!checks.any((check) =>
          check.endpoint.signature == node.signature && check.available)) {
        _successes.remove(node.signature);
      }
    }
    if (_lastSample != null &&
        now.difference(_lastSample!) < const Duration(seconds: 30)) {
      return null;
    }
    _lastSample = now;
    for (final node in NodeEndpoint.builtIn) {
      if (checks.any((check) =>
          check.endpoint.signature == node.signature && check.available)) {
        _successes[node.signature] = (_successes[node.signature] ?? 0) + 1;
      }
    }
    for (final node in NodeEndpoint.builtIn) {
      if ((_successes[node.signature] ?? 0) >= 3) return node;
    }
    return null;
  }
}
