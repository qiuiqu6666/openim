import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../server_nodes/node_availability_probe.dart';
import '../../server_nodes/node_endpoint.dart';

/// One foreground API check loop per SDK login session. No user credentials.
class ApiConnectionHealth with WidgetsBindingObserver {
  ApiConnectionHealth(
      {required this.isCurrent,
      Future<bool> Function()? check,
      Stream<List<ConnectivityResult>>? networkChanges})
      : _check = check ?? _probe,
        _networkChanges = networkChanges;

  final bool Function() isCurrent;
  final Future<bool> Function() _check;
  final Stream<List<ConnectivityResult>>? _networkChanges;
  StreamSubscription<List<ConnectivityResult>>? _network;
  final available = ValueNotifier<bool?>(null);

  /// End-to-end API check duration, including network and server response.
  final latencyMs = ValueNotifier<int?>(null);
  Timer? _timer;
  bool _active = false;
  bool _foreground = true;
  bool _checking = false;
  bool _online = true;
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
      if (!_active) return;
      _online = results.any((result) => result != ConnectivityResult.none);
      _revision++;
      latencyMs.value = null;
      if (!_online) {
        available.value = false;
        _timer?.cancel();
        return;
      }
      if (_active &&
          _foreground &&
          isCurrent() &&
          results.any((result) => result != ConnectivityResult.none)) {
        _revision++;
        _failures = 0;
        _timer?.cancel();
        unawaited(_refresh());
      }
    }, onError: (Object _) {});
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!_active || !_foreground || !_online || _checking || !isCurrent()) {
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
    if (!_active || !_foreground || !_online || !isCurrent()) return;
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
    _revision++;
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    latencyMs.value = null;
    if (_foreground) {
      _failures = 0;
      available.value = null;
      unawaited(_refresh());
    }
  }

  void close() {
    _active = false;
    _timer?.cancel();
    unawaited(_network?.cancel());
    _network = null;
    WidgetsBinding.instance.removeObserver(this);
    available.dispose();
    latencyMs.dispose();
  }
}
