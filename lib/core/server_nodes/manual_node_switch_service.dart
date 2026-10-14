import 'node_availability_probe.dart';
import 'node_endpoint.dart';

enum NodeSwitchFailure {
  busy,
  unavailable,
  sessionChanged,
  connectionFailed,
  recoveryFailed,
}

/// Coordinates an explicit route change. Automatic probes never call this.
class ManualNodeSwitchService {
  ManualNodeSwitchService({
    required this.readSession,
    required this.canSwitch,
    required this.connect,
    NodeEndpoint Function()? readEndpoint,
    Future<NodeAvailability> Function(NodeEndpoint)? probe,
    this.prepareTarget,
  })  : readEndpoint = readEndpoint ?? NodeEndpoint.current,
        probe = probe ?? NodeAvailabilityProbe().check;

  final Object? Function() readSession;
  final bool Function() canSwitch;
  final NodeEndpoint Function() readEndpoint;
  final Future<NodeAvailability> Function(NodeEndpoint) probe;
  final Future<void> Function(NodeEndpoint)? prepareTarget;
  final Future<void> Function(NodeEndpoint, bool Function()) connect;
  bool busy = false;

  Future<void> switchTo(NodeEndpoint target,
      {required bool Function() isActive, bool allowShield = false}) async {
    if (busy || !canSwitch()) throw NodeSwitchFailure.busy;
    final session = readSession();
    if (session == null) throw NodeSwitchFailure.sessionChanged;
    final previous = readEndpoint();
    if (!(allowShield &&
            [...NodeEndpoint.builtIn, NodeEndpoint.shield]
                .any((node) => node.signature == previous.signature) &&
            [...NodeEndpoint.builtIn, NodeEndpoint.shield]
                .any((node) => node.signature == target.signature)) &&
        !NodeEndpoint.candidates(previous)
            .any((node) => node.signature == target.signature)) {
      throw NodeSwitchFailure.unavailable;
    }
    busy = true;
    bool sameSession() => readSession() == session;
    try {
      try {
        await prepareTarget?.call(target);
      } catch (_) {
        throw NodeSwitchFailure.unavailable;
      }
      final result = await probe(target);
      if (!sameSession() ||
          !isActive() ||
          readEndpoint().signature != previous.signature) {
        throw NodeSwitchFailure.sessionChanged;
      }
      if (!canSwitch()) throw NodeSwitchFailure.busy;
      if (!result.available) throw NodeSwitchFailure.unavailable;
      try {
        await connect(target, sameSession);
        if (!sameSession()) throw NodeSwitchFailure.sessionChanged;
      } catch (_) {
        // Never restore an old account after logout or account replacement.
        if (!sameSession()) throw NodeSwitchFailure.sessionChanged;
        try {
          await connect(previous, sameSession);
        } catch (_) {
          if (!sameSession()) throw NodeSwitchFailure.sessionChanged;
          throw NodeSwitchFailure.recoveryFailed;
        }
        throw NodeSwitchFailure.connectionFailed;
      }
    } finally {
      busy = false;
    }
  }
}
