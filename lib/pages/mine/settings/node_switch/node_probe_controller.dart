import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../../../services/platform_config_service.dart';
import '../../../../core/server_nodes/manual_node_switch_runtime.dart';
import '../../../../core/server_nodes/manual_node_switch_service.dart';
import 'node_endpoint.dart';

enum NodeProbeStatus { unknown, normal, abnormal }

class NodeProbeResult {
  const NodeProbeResult(this.status, {this.latencyMs, this.httpStatus});
  final NodeProbeStatus status;
  final int? latencyMs, httpStatus;
}

/// Node page state: public probes and explicit, separately coordinated switches.
class NodeProbeController extends ChangeNotifier with WidgetsBindingObserver {
  NodeProbeController(
      {NodeEndpoint Function()? readEndpoint,
      Dio Function()? clientFactory,
      ManualNodeSwitchService? switchService})
      : _readEndpoint = readEndpoint ?? NodeEndpoint.current,
        _switchService = switchService ?? ManualNodeSwitchRuntime.instance,
        _clientFactory = clientFactory ??
            (() => Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                followRedirects: false))) {
    endpoint = _readEndpoint();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  final NodeEndpoint Function() _readEndpoint;
  final Dio Function() _clientFactory;
  final ManualNodeSwitchService _switchService;
  NodeEndpoint? switchingTo;
  bool get switching => switchingTo != null;
  bool connectionUnconfirmed = false;
  late NodeEndpoint endpoint;
  NodeProbeStatus status = NodeProbeStatus.unknown;
  bool testing = false;
  bool hasManualTest = false;
  int? latencyMs, httpStatus;
  DateTime? testedAt;
  bool _disposed = false, _foreground = true;
  int _generation = 0;
  CancelToken? _token;
  Future<void>? _work;
  final Map<String, NodeProbeResult> results = {};
  final Set<String> pending = {};

  Future<NodeSwitchFailure?> switchTo(NodeEndpoint node) async {
    if (_disposed || !_foreground) return NodeSwitchFailure.sessionChanged;
    if (testing || switching) return NodeSwitchFailure.busy;
    if (node.signature == endpoint.signature && !connectionUnconfirmed) {
      return null;
    }
    switchingTo = node;
    notifyListeners();
    NodeSwitchFailure? failure;
    try {
      await _switchService.switchTo(node,
          isActive: () => !_disposed && _foreground);
      connectionUnconfirmed = false;
    } on NodeSwitchFailure catch (error) {
      failure = error;
      connectionUnconfirmed = error == NodeSwitchFailure.recoveryFailed;
    } catch (_) {
      failure = NodeSwitchFailure.connectionFailed;
    } finally {
      switchingTo = null;
      if (!_disposed) {
        endpoint = _readEndpoint();
        notifyListeners();
      }
    }
    return failure;
  }

  Future<void> test() {
    if (_disposed || !_foreground || switching) return Future.value();
    if (_work != null) return _work!;
    endpoint = _readEndpoint();
    testing = true;
    hasManualTest = true;
    status = NodeProbeStatus.unknown;
    latencyMs = httpStatus = null;
    testedAt = null;
    results.clear();
    final nodes = NodeEndpoint.candidates(endpoint);
    pending.clear();
    pending.addAll(nodes.map((node) => node.signature));
    final generation = ++_generation;
    final token = _token = CancelToken();
    late final Future<void> work;
    work = Future.wait(
            nodes.map((node) => _probe(node, endpoint, generation, token)))
        .then((_) {
      if (_disposed || generation != _generation) return;
      testing = false;
      pending.clear();
      if (_current(generation, endpoint)) {
        testedAt = DateTime.now();
      } else {
        endpoint = _readEndpoint();
        results.clear();
        status = NodeProbeStatus.unknown;
        latencyMs = httpStatus = null;
      }
      notifyListeners();
    }).whenComplete(() {
      if (identical(_work, work)) {
        _work = null;
        _token = null;
      }
    });
    _work = work;
    notifyListeners();
    return work;
  }

  bool _current(int generation, NodeEndpoint requested) =>
      !_disposed &&
      _foreground &&
      generation == _generation &&
      requested.signature == _readEndpoint().signature;

  Future<void> _probe(NodeEndpoint requested, NodeEndpoint active,
      int generation, CancelToken token) async {
    Dio? client;
    var result = const NodeProbeResult(NodeProbeStatus.abnormal);
    final watch = Stopwatch()..start();
    try {
      final uri = Uri.tryParse(requested.chatApi);
      if (uri == null ||
          !const {'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException('Invalid Chat endpoint');
      }
      client = _clientFactory();
      await PlatformConfigService.fetch(
          client: client, baseUrl: requested.chatApi, cancelToken: token);
      result = NodeProbeResult(NodeProbeStatus.normal,
          latencyMs: watch.elapsedMilliseconds);
    } catch (error) {
      result = NodeProbeResult(NodeProbeStatus.abnormal,
          httpStatus:
              error is DioException ? error.response?.statusCode : null);
    } finally {
      watch.stop();
      client?.close(force: true);
      if (_current(generation, active)) {
        results[requested.signature] = result;
        pending.remove(requested.signature);
        if (requested.signature == active.signature) {
          status = result.status;
          latencyMs = result.latencyMs;
          httpStatus = result.httpStatus;
        }
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && !_disposed) {
      _generation++;
      _token?.cancel('Node probe suspended');
      _token = null;
      _work = null;
      testing = false;
      pending.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _token?.cancel('Node probe closed');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
