import 'package:openim_common/openim_common.dart';

import 'node_availability_probe.dart';
import 'node_endpoint.dart';
import 'timed_node_probe.dart';

class NodeSelection {
  NodeSelection(this.selected, this.checks) : checkedAt = DateTime.now();
  final NodeEndpoint selected;
  final List<NodeAvailability> checks;
  final DateTime checkedAt;
}

class StartupNodeSelector {
  StartupNodeSelector({
    Future<NodeAvailability> Function(NodeEndpoint)? probe,
    NodeEndpoint Function()? readCurrent,
    Future<void> Function(NodeEndpoint)? apply,
    this.preferred,
  })  : _probe = probe ??
            NodeAvailabilityProbe(timeout: const Duration(milliseconds: 2250))
                .check,
        _readCurrent = readCurrent ?? NodeEndpoint.current,
        _apply = apply ?? persist;

  final Future<NodeAvailability> Function(NodeEndpoint) _probe;
  final NodeEndpoint Function() _readCurrent;
  final Future<void> Function(NodeEndpoint) _apply;
  Future<NodeSelection>? _pending;
  final NodeEndpoint? preferred;

  Future<NodeSelection> select() => _pending ??= _select().whenComplete(() {
        _pending = null;
      });

  Future<NodeSelection> _select() async {
    final current = _readCurrent();
    final candidates = [...NodeEndpoint.candidates(current)];
    final index =
        candidates.indexWhere((node) => node.signature == preferred?.signature);
    if (index > 0) candidates.insert(0, candidates.removeAt(index));
    final checks = await TimedNodeProbe(probe: _probe).check(candidates);
    // Prefer the first healthy built-in route. Custom deployments stay isolated.
    var selected = current;
    for (final check in checks) {
      if (check.available) {
        selected = check.endpoint;
        break;
      }
    }
    if (_readCurrent().signature != current.signature) {
      return NodeSelection(_readCurrent(), checks);
    }
    if (selected.signature != current.signature ||
        (selected.customerServiceUrl != null &&
            selected.customerServiceUrl != current.customerServiceUrl)) {
      try {
        await _apply(selected);
      } catch (_) {
        selected = current;
      }
    }
    return NodeSelection(selected, checks);
  }

  static Future<void> persist(NodeEndpoint node) async {
    final previous = DataSp.getServerConfig();
    final config = <String, String>{
      if (previous != null)
        for (final entry in previous.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      'authUrl': node.chatApi,
      'apiUrl': node.imApi,
      'wsUrl': node.imWs,
      if (node.customerServiceUrl != null)
        'customerServiceUrl': node.customerServiceUrl!,
    };
    if (await DataSp.putServerConfig(config) != true) {
      throw StateError('Could not persist the selected node');
    }
  }
}

/// Runs once during each process startup, before HTTP and SDK initialization.
/// No foreground observer: active chat/call sessions keep their connection.
class StartupNodeSelection {
  static NodeSelection? last;

  static Future<void> prepare() async {
    last = await StartupNodeSelector().select();
  }
}
