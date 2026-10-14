import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../network/transport_state.dart';

import '../../server_nodes/node_availability_probe.dart';
import '../../server_nodes/node_endpoint.dart';

/// One foreground API check loop per SDK login session. No user credentials.
class ApiConnectionHealth with WidgetsBindingObserver {
  ApiConnectionHealth(
      {required this.isCurrent,
      Future<bool> Function()? check,
      Stream<List<ConnectivityResult>>? networkChanges,
      Future<List<ConnectivityResult>> Function()? networkSnapshot})
      : _check = check ?? _probe,
        _networkChanges = networkChanges,
        _networkSnapshot = networkSnapshot ??
            (networkChanges == null ? Connectivity().checkConnectivity : null);

  final bool Function() isCurrent;
  final Future<bool> Function() _check;
  final Stream<List<ConnectivityResult>>? _networkChanges;
  final Future<List<ConnectivityResult>> Function()? _networkSnapshot;
  StreamSubscription<List<ConnectivityResult>>? _network;
  final available = ValueNotifier<bool?>(null);

  /// End-to-end API check duration, including network and server response.
  final latencyMs = ValueNotifier<int?>(null);
  Timer? _timer;
  bool _active = false;
  bool _foreground = true;
  bool _checking = false;
  final _transport = NetworkTransportState();
  int _revision = 0;
  int _failures = 0;
  static const _retrySeconds = [3, 6, 12, 30];

  static Future<bool> _probe() async => (await NodeAvailabilityProbe()
          .check(NodeEndpoint.current(), includeGateway: false))
      .available;

  void start() {
    if (_active) return;
    _active = true;
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _network = (_networkChanges ?? Connectivity().onConnectivityChanged).listen(
        (results) {
      if (!_active || !_transport.update(results)) return;
      _transportChanged();
    }, onError: (Object _) {});
    unawaited(_refresh());
    unawaited(_refreshTransport());
  }

  void _transportChanged() {
    _revision++;
    latencyMs.value = null;
    _timer?.cancel();
    if (!_transport.online) {
      available.value = false;
    } else if (_foreground && isCurrent()) {
      _failures = 0;
      unawaited(_refresh());
    }
  }

  Future<void> _refreshTransport() async {
    final read = _networkSnapshot;
    if (read == null || !_active || !_foreground || !isCurrent()) return;
    final changed = await _transport.refresh(read);
    if (changed && _active && _foreground && isCurrent()) _transportChanged();
  }

  Future<void> _refresh() async {
    if (!_active ||
        !_foreground ||
        !_transport.online ||
        _checking ||
        !isCurrent()) {
      return;
    }
    _checking = true;
    final revision = _revision;
    final route = NodeEndpoint.current().signature;
    final watch = Stopwatch()..start();
    var healthy = false;
    try {
      healthy = await _check().timeout(const Duration(seconds: 4));
    } catch (_) {
      healthy = false;
    } finally {
      watch.stop();
      _checking = false;
    }
    if (!_active || !_foreground || !_transport.online || !isCurrent()) return;
    if (revision != _revision || route != NodeEndpoint.current().signature) {
      available.value = null;
      latencyMs.value = null;
      unawaited(_refresh());
      return;
    }
    latencyMs.value = healthy ? watch.elapsedMilliseconds : null;
    available.value = healthy;
    _timer?.cancel();
    if (healthy) _failures = 0;
    final seconds = healthy ? 5 : _retrySeconds[_failures];
    if (!healthy && _failures < _retrySeconds.length - 1) _failures++;
    _timer = Timer(Duration(seconds: seconds), _refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _revision++;
    _foreground = foreground;
    if (!_foreground) _transport.invalidateSnapshot();
    _timer?.cancel();
    latencyMs.value = null;
    if (_foreground) {
      unawaited(_refreshTransport());
      _failures = 0;
      available.value = null;
      unawaited(_refresh());
    }
  }

  void close() {
    _active = false;
    _transport.invalidateSnapshot();
    _timer?.cancel();
    unawaited(_network?.cancel());
    _network = null;
    WidgetsBinding.instance.removeObserver(this);
    available.dispose();
    latencyMs.dispose();
  }
}
