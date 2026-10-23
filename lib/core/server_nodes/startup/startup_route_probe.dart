import 'dart:async';
import 'package:dio/dio.dart';
import '../node_endpoint.dart';
import '../public_health_check.dart';
import 'startup_state.dart';

/// Emits API readiness independently from gateway health. All three requests
/// run concurrently; a gateway failure never cancels the authentication probes.
class StartupRouteProbe {
  StartupRouteProbe({Dio Function()? clientFactory})
      : _clientFactory = clientFactory ?? (() => Dio());
  final Dio Function() _clientFactory;
  final _active = <CancelToken, Dio>{};

  Future<void> check(
      NodeEndpoint node, int generation, void Function(StartupHealth) onHealth,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final client = _clientFactory();
    final token = CancelToken();
    _active[token] = client;
    PublicHealthCheck.isolate(client, timeout);
    final states = {'chat': 'pending', 'imApi': 'pending', 'imWs': 'pending'};
    Future<void> run(String name, Future<void> Function() request) async {
      try {
        await request().timeout(timeout);
        states[name] = 'ok';
      } catch (error) {
        states[name] = error is DioException
            ? error.type.name
            : error.runtimeType.toString();
      }
      if (!token.isCancelled) onHealth(StartupHealth(node, generation, states));
    }

    try {
      await Future.wait([
        run(
            'chat',
            () => PublicHealthCheck.get(client, node.chatApi,
                service: 'chat-api', cancelToken: token)),
        run(
            'imApi',
            () => PublicHealthCheck.get(client, node.imApi,
                service: 'openim-api', cancelToken: token)),
        run('imWs', () => PublicHealthCheck.gateway(client, node.imWs, token)),
      ]);
    } finally {
      token.cancel('Startup probe finished');
      client.close(force: true);
      _active.remove(token);
    }
  }

  void cancel() {
    for (final entry in _active.entries.toList()) {
      entry.key.cancel('Startup generation changed');
      entry.value.close(force: true);
    }
    _active.clear();
  }
}
