import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../../../services/platform_config_service.dart';
import 'node_endpoint.dart';

enum NodeProbeStatus { unknown, normal, abnormal }

/// A manual public Chat probe; never changes login credentials or SDK endpoints.
class NodeProbeController extends ChangeNotifier with WidgetsBindingObserver {
  NodeProbeController(
      {NodeEndpoint Function()? readEndpoint, Dio Function()? clientFactory})
      : _readEndpoint = readEndpoint ?? NodeEndpoint.current,
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
  late NodeEndpoint endpoint;
  NodeProbeStatus status = NodeProbeStatus.unknown;
  bool testing = false;
  int? latencyMs, httpStatus;
  DateTime? testedAt;
  bool _disposed = false, _foreground = true;
  int _generation = 0;
  CancelToken? _token;
  Future<void>? _work;

  Future<void> test() {
    if (_disposed || !_foreground) return Future.value();
    if (_work != null) return _work!;
    endpoint = _readEndpoint();
    testing = true;
    status = NodeProbeStatus.unknown;
    latencyMs = httpStatus = null;
    final generation = ++_generation;
    final token = _token = CancelToken();
    late final Future<void> work;
    work = _probe(endpoint, generation, token).whenComplete(() {
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

  Future<void> _probe(
      NodeEndpoint requested, int generation, CancelToken token) async {
    Dio? client;
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
      if (_current(generation, requested)) {
        latencyMs = watch.elapsedMilliseconds;
        status = NodeProbeStatus.normal;
      }
    } catch (error) {
      if (_current(generation, requested)) {
        status = NodeProbeStatus.abnormal;
        if (error is DioException) httpStatus = error.response?.statusCode;
      }
    } finally {
      watch.stop();
      client?.close(force: true);
      if (!_disposed && generation == _generation) {
        if (!_current(generation, requested)) {
          endpoint = _readEndpoint();
          status = NodeProbeStatus.unknown;
          latencyMs = httpStatus = null;
        } else {
          testedAt = DateTime.now();
        }
        testing = false;
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
