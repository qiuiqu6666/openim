import 'package:flutter_test/flutter_test.dart';
import 'package:gameshield_bridge/gameshield_bridge.dart';
import 'package:openim/core/gameshield/gameshield_failure.dart';
import 'package:openim/core/gameshield/gameshield_routes.dart';
import 'package:openim/core/gameshield/gameshield_settings.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';

void main() {
  test(
      'shared application and group resolve by original TCP ports after relocation',
      () {
    const rule = GameShieldRule('package-id', groupName: 'GW-FE0AE76E');
    const sharedSettings = GameShieldSettings(
        auth: rule, imApi: rule, imWs: rule, customerService: rule);
    final sharedSnapshot = GameShieldSnapshot.fromMap({
      'ready': true,
      'sdkVersion': '60.1.10',
      'activeTunnels': 4,
      'tcpPorts': {
        '10008': 40008,
        '10002': 40002,
        '10001': 40001,
        '8815': 48815
      },
      'endpoints': [48815, 40001, 40008, 40002]
          .map((port) => {
                'appId': 'package-id',
                'groupName': 'GW-FE0AE76E',
                'host': '127.0.0.1',
                'port': port,
                'protocol': 'TCP',
              })
          .toList(),
    });
    final route = GameShieldRoutes.resolve(
        sharedSettings, sharedSnapshot, NodeEndpoint.direct);
    expect(route.authUrl, 'http://127.0.0.1:40008');
    expect(route.apiUrl, 'http://127.0.0.1:40002');
    expect(route.wsUrl, 'ws://127.0.0.1:40001');
    expect(route.customerServiceUrl, 'http://127.0.0.1:48815');
    for (final ports in <Map<int, int>>[
      {},
      {10008: 0},
      {10008: 65536},
      {10008: 40008, 10002: 40008, 10001: 40001, 8815: 48815}
    ]) {
      final invalid = GameShieldSnapshot(
          ready: true,
          sdkVersion: '60.1.10',
          activeTunnels: 4,
          endpoints: sharedSnapshot.endpoints,
          tcpPorts: ports);
      expect(
          () => GameShieldRoutes.resolve(
              sharedSettings, invalid, NodeEndpoint.direct),
          throwsA(isA<GameShieldFailure>()));
    }
  });
  const settings = GameShieldSettings(
      enabled: true,
      auth: GameShieldRule('app', groupName: 'auth'),
      imApi: GameShieldRule('app', groupName: 'api'),
      imWs: GameShieldRule('app', groupName: 'ws'),
      customerService: GameShieldRule('app', groupName: '客服服务1'));
  const snapshot = GameShieldSnapshot(
      ready: true,
      sdkVersion: '60.1.10',
      activeTunnels: 0,
      endpoints: [
        GameShieldEndpoint(
            appId: 'app',
            groupName: 'auth',
            host: '::1',
            port: 30008,
            protocol: 'tcp'),
        GameShieldEndpoint(
            appId: 'app',
            groupName: 'api',
            host: '::1',
            port: 30002,
            protocol: 'tcp'),
        GameShieldEndpoint(
            appId: 'app',
            groupName: 'ws',
            host: '::1',
            port: 30001,
            protocol: 'tcp'),
        GameShieldEndpoint(
            appId: 'app',
            groupName: '客服服务1',
            host: '::1',
            port: 38815,
            protocol: 'tcp'),
      ]);
  test('group selectors disambiguate shared app IDs and IPv6 URLs remain valid',
      () {
    final route =
        GameShieldRoutes.resolve(settings, snapshot, NodeEndpoint.direct);
    expect(route.authUrl, 'http://[::1]:30008');
    expect(route.apiUrl, 'http://[::1]:30002');
    expect(route.wsUrl, 'ws://[::1]:30001');
    expect(route.customerServiceUrl, 'http://[::1]:38815');
  });
  test('TLS URL is never rewritten to a loopback IP without preserving SNI',
      () {
    const tls = NodeEndpoint(
        chatApi: 'https://chat.example',
        imApi: 'https://api.example',
        imWs: 'wss://ws.example');
    expect(
        () => GameShieldRoutes.resolve(settings, snapshot, tls),
        throwsA(isA<GameShieldFailure>().having((error) => error.kind, 'kind',
            GameShieldFailureKind.configuration)));
  });
  test('same local socket cannot silently map different origin services', () {
    final shared = GameShieldSnapshot(
        ready: true,
        sdkVersion: '60.1.10',
        activeTunnels: 0,
        endpoints: snapshot.endpoints
            .map((endpoint) => GameShieldEndpoint(
                appId: endpoint.appId,
                groupName: endpoint.groupName,
                host: endpoint.host,
                port: 30000,
                protocol: 'tcp'))
            .toList());
    expect(
        () => GameShieldRoutes.resolve(settings, shared, NodeEndpoint.direct),
        throwsA(isA<GameShieldFailure>().having((error) => error.kind, 'kind',
            GameShieldFailureKind.invalidEndpoints)));
  });
}
