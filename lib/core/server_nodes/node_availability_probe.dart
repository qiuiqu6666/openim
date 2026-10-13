import 'dart:async';

import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/platform_config_service.dart';
import 'node_endpoint.dart';

class NodeAvailability {
  const NodeAvailability(this.endpoint,
      {required this.available, required this.latencyMs});
  final NodeEndpoint endpoint;
  final bool available;
  final int latencyMs;
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

  Future<NodeAvailability> check(NodeEndpoint node,
      {bool includeGateway = true}) async {
    final watch = Stopwatch()..start();
    final client = _clientFactory();
    final token = CancelToken();
    client.options
      ..connectTimeout = timeout
      ..receiveTimeout = timeout
      ..sendTimeout = timeout
      ..followRedirects = false;
    var available = false;
    try {
      final chat = _uri(node.chatApi, const {'http', 'https'});
      final api = _uri(node.imApi, const {'http', 'https'});
      final ws = _uri(node.imWs, const {'ws', 'wss'});
      await Future.wait([
        PlatformConfigService.fetch(
            client: client, baseUrl: chat.toString(), cancelToken: token),
        _api(client, api, token),
        if (includeGateway) _gateway(client, ws, token),
      ], eagerError: true)
          .timeout(timeout);
      available = true;
    } catch (_) {
      // Offline/partial failures leave this entire route unavailable.
    } finally {
      token.cancel('Node availability check finished');
      client.close(force: true);
      watch.stop();
    }
    return NodeAvailability(node,
        available: available, latencyMs: watch.elapsedMilliseconds);
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

  Future<void> _api(Dio client, Uri base, CancelToken token) async {
    final response = await client.post<Map<String, dynamic>>(
        '$base/user/get_users_info',
        data: <String, dynamic>{},
        cancelToken: token,
        options: Options(headers: {'operationID': HttpUtil.operationID}));
    final body = response.data;
    // This read-only route must reach OpenIM's missing-token validation.
    if (response.statusCode != 200 ||
        body?['errCode'] != 1001 ||
        body?['errDlt'] is! String ||
        !(body!['errDlt'] as String).contains('token')) {
      throw StateError('IM API unavailable');
    }
  }

  Future<void> _gateway(Dio client, Uri ws, CancelToken token) async {
    final response = await client.get<Map<String, dynamic>>(
        ws.replace(scheme: ws.scheme == 'wss' ? 'https' : 'http').toString(),
        cancelToken: token);
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
