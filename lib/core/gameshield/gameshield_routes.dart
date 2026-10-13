import 'dart:io';
import 'package:gameshield_bridge/gameshield_bridge.dart';
import 'package:openim_common/openim_common.dart';
import '../server_nodes/node_endpoint.dart';
import 'gameshield_failure.dart';
import 'gameshield_settings.dart';

class GameShieldRoutes {
  static RuntimeNetworkRoute resolve(GameShieldSettings settings,
      GameShieldSnapshot snapshot, NodeEndpoint origin) {
    if (!snapshot.ready || snapshot.sdkVersion != '60.1.10') {
      throw const GameShieldFailure(GameShieldFailureKind.invalidEndpoints);
    }
    String address(GameShieldRule rule, String original) {
      final uri = Uri.parse(original);
      // TLS forwarding needs a separate transport that preserves SNI. This
      // preparation only enables the current HTTP/WS deployment.
      if (!const {'http', 'ws'}.contains(uri.scheme)) {
        throw const GameShieldFailure(GameShieldFailureKind.configuration);
      }
      var matches = snapshot.endpoints
          .where((endpoint) =>
              endpoint.appId == rule.appId.trim() &&
              (rule.groupName.isEmpty ||
                  endpoint.groupName == rule.groupName) &&
              endpoint.protocol.toLowerCase() == 'tcp')
          .toList();
      if (matches.length > 1) {
        final actualPort = snapshot.tcpPorts[uri.port];
        matches =
            matches.where((endpoint) => endpoint.port == actualPort).toList();
      }
      if (matches.length != 1) {
        throw const GameShieldFailure(GameShieldFailureKind.invalidEndpoints);
      }
      final endpoint = matches.single;
      final ip = InternetAddress.tryParse(endpoint.host);
      if (ip == null ||
          !ip.isLoopback ||
          endpoint.port < 1 ||
          endpoint.port > 65535) {
        throw const GameShieldFailure(GameShieldFailureKind.invalidEndpoints);
      }
      return uri.replace(host: endpoint.host, port: endpoint.port).toString();
    }

    final route = RuntimeNetworkRoute(
      authUrl: address(settings.auth, origin.chatApi),
      apiUrl: address(settings.imApi, origin.imApi),
      wsUrl: address(settings.imWs, origin.imWs),
      customerServiceUrl:
          address(settings.customerService, settings.customerServiceBaseUrl),
    );
    // Different upstream services must not accidentally select one rule.
    final sockets = [
      route.authUrl,
      route.apiUrl,
      route.wsUrl,
      route.customerServiceUrl
    ].map(Uri.parse).map((uri) => '${uri.host}:${uri.port}').toSet();
    if (sockets.length != 4) {
      throw const GameShieldFailure(GameShieldFailureKind.invalidEndpoints);
    }
    return route;
  }
}
