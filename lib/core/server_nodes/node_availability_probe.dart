import 'dart:async';

import 'package:dio/dio.dart';
import 'node_endpoint.dart';
import 'public_health_check.dart';

class NodeAvailability {
  const NodeAvailability(this.endpoint,
      {required this.available,
      required this.latencyMs,
      this.serviceFailures = const {}});
  final NodeEndpoint endpoint;
  final bool available;
  final int latencyMs;

  /// Service names and sanitized failure categories; never URLs or credentials.
  final Map<String, String> serviceFailures;
}

/// Credential-free checks of the Chat API, IM API and WebSocket gateway.
/// Authenticated SDK login remains responsible for validating the session.
class NodeAvailabilityProbe {
  NodeAvailabilityProbe({
    Dio Function()? clientFactory,
    this.timeout = const Duration(seconds: 3),
  }) : _clientFactory = clientFactory ?? (() => Dio());

  final Dio Function() _clientFactory;
  final Duration timeout;
  final _pendingChecks = <String, Future<NodeAvailability>>{};
  final _tokens = <CancelToken>{};

  /// One in-flight check per candidate and check mode for this owner.
  Future<NodeAvailability> check(NodeEndpoint node,
      {bool includeGateway = true}) {
    final key = '${node.signature}|$includeGateway';
    return _pendingChecks.putIfAbsent(key, () {
      late final Future<NodeAvailability> work;
      work = _check(node, includeGateway: includeGateway).whenComplete(() {
        if (identical(_pendingChecks[key], work)) _pendingChecks.remove(key);
      });
      return work;
    });
  }

  void cancel() {
    for (final token in _tokens.toList()) {
      token.cancel('Line probe superseded');
    }
    _pendingChecks.clear();
  }

  Future<NodeAvailability> _check(NodeEndpoint node,
      {bool includeGateway = true}) async {
    final watch = Stopwatch()..start();
    final client = _clientFactory();
    final token = CancelToken();
    _tokens.add(token);
    PublicHealthCheck.isolate(client, timeout);
    var available = false;
    final failures = <String, String>{};
    final pending = <String>{};
    Future<void> track(String service, Future<dynamic> work) async {
      pending.add(service);
      try {
        await work;
      } catch (error) {
        failures[service] = error is DioException
            ? '${error.type.name}${error.response?.statusCode == null ? '' : ':${error.response!.statusCode}'}'
            : error.runtimeType.toString();
        rethrow;
      } finally {
        pending.remove(service);
      }
    }

    try {
      final chat = _uri(node.chatApi, const {'http', 'https'});
      final api = _uri(node.imApi, const {'http', 'https'});
      final ws = _uri(node.imWs, const {'ws', 'wss'});
      await Future.wait([
        track(
            'chat',
            PublicHealthCheck.get(client, chat.toString(),
                service: 'chat-api', cancelToken: token)),
        track(
            'imApi',
            PublicHealthCheck.get(client, api.toString(),
                service: 'openim-api', cancelToken: token)),
        if (includeGateway) track('imWs', _gateway(client, ws, token)),
      ], eagerError: true)
          .timeout(timeout);
      available = true;
    } catch (error) {
      // Offline/partial failures leave this entire route unavailable.
      for (final service in pending) {
        failures.putIfAbsent(
            service, () => error is TimeoutException ? 'timeout' : 'cancelled');
      }
      if (failures.isEmpty) failures['endpoint'] = error.runtimeType.toString();
    } finally {
      token.cancel('Node availability check finished');
      _tokens.remove(token);
      client.close(force: true);
      watch.stop();
    }
    return NodeAvailability(node,
        available: available,
        latencyMs: watch.elapsedMilliseconds,
        serviceFailures: Map.unmodifiable(failures));
  }

  Uri _uri(String value, Set<String> schemes) {
    final uri = Uri.parse(value.trim().replaceFirst(RegExp(r'/+$'), ''));
    if (!schemes.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid node address');
    }
    return uri;
  }

  Future<void> _gateway(Dio client, Uri ws, CancelToken token) async {
    final response = await client.get<Map<String, dynamic>>(
        ws.replace(scheme: ws.scheme == 'wss' ? 'https' : 'http').toString(),
        cancelToken: token,
        options: Options(headers: await PublicHealthCheck.diagnosticHeaders()));
    final body = response.data;
    // An unauthenticated gateway returns the OpenIM argument error rather
    // than opening a user connection. Reject proxies, HTML and server errors.
    if (response.statusCode != 200 ||
        body?['errCode'] != 1602 ||
        body?['errMsg'] is! String ||
        !(body!['errMsg'] as String).contains('token')) {
      throw StateError('WebSocket gateway unavailable');
    }
  }
}
