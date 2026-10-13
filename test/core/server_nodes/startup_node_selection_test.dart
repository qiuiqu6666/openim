import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/startup_node_selection.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

NodeAvailability result(NodeEndpoint node, bool available) =>
    NodeAvailability(node, available: available, latencyMs: 10);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    StartupNodeSelection.last = null;
  });

  test('retired domain node uses direct even offline and preserves credentials',
      () async {
    await DataSp.putServerConfig({
      'authUrl': 'https://99chatapi.99chat.vip',
      'apiUrl': 'https://99imapi.99chat.vip',
      'wsUrl': 'wss://websocket.99chat.vip',
      'logLevel': '4',
    });
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'u',
      'imToken': 'im-secret',
      'chatToken': 'chat-secret',
    }));
    final probed = <NodeEndpoint>[];
    final selected = await StartupNodeSelector(probe: (node) async {
      probed.add(node);
      return result(node, false);
    }).select();
    expect(probed, [NodeEndpoint.direct]);
    expect(selected.selected.signature, NodeEndpoint.direct.signature);
    expect(NodeEndpoint.current().signature, NodeEndpoint.direct.signature);
    expect(DataSp.getServerConfig()?['logLevel'], '4');
    expect(DataSp.imToken, 'im-secret');
    expect(DataSp.chatToken, 'chat-secret');
  });

  test('each launch rechecks only the direct route', () async {
    final probed = <NodeEndpoint>[];
    await StartupNodeSelector(probe: (node) async {
      probed.add(node);
      return result(node, false);
    }).select();
    final selected = await StartupNodeSelector(probe: (node) async {
      probed.add(node);
      return result(node, true);
    }).select();
    expect(probed, [NodeEndpoint.direct, NodeEndpoint.direct]);
    expect(selected.selected, NodeEndpoint.direct);
    expect(NodeEndpoint.current().signature, NodeEndpoint.direct.signature);
  });

  test('saved production IP migrates to new hostname with the same ports', () async {
    await DataSp.putServerConfig({
      'serverIP': '129.226.192.93',
      'authUrl': 'http://129.226.192.93:10008',
      'apiUrl': 'http://129.226.192.93:10002',
      'wsUrl': 'ws://129.226.192.93:10001',
    });
    const host = 'lhins-14l2mj2j.3w3hbb07j0xz.eo.dnse5.com';
    expect(Config.serverIp, host);
    expect(Config.appAuthUrl, 'http://$host:10008');
    expect(Config.imApiUrl, 'http://$host:10002');
    expect(Config.imWsUrl, 'ws://$host:10001');
    expect(NodeEndpoint.current().signature, NodeEndpoint.direct.signature);
  });

  test('offline startup keeps the last endpoint and does not clear credentials',
      () async {
    await StartupNodeSelector(
            probe: (node) async => result(node, node == NodeEndpoint.direct))
        .select();
    final selected =
        await StartupNodeSelector(probe: (node) async => result(node, false))
            .select();
    expect(selected.selected.signature, NodeEndpoint.direct.signature);
    expect(NodeEndpoint.current().signature, NodeEndpoint.direct.signature);
    expect(selected.checks.every((check) => !check.available), isTrue);
  });

  test('custom deployment is never replaced by production routes', () async {
    const custom = NodeEndpoint(
        chatApi: 'https://custom.test/chat',
        imApi: 'https://custom.test/api',
        imWs: 'wss://custom.test/ws');
    final probed = <NodeEndpoint>[];
    final selected = await StartupNodeSelector(
        readCurrent: () => custom,
        apply: (_) async => fail('Must not replace a custom deployment'),
        probe: (node) async {
          probed.add(node);
          return result(node, false);
        }).select();
    expect(probed, [custom]);
    expect(selected.selected, custom);
  });

  test('concurrent calls share probes and a later selection probes again',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final selector = StartupNodeSelector(probe: (node) async {
      calls++;
      await gate.future;
      return result(node, true);
    });
    final first = selector.select();
    expect(identical(first, selector.select()), isTrue);
    expect(calls, 1);
    gate.complete();
    await first;
    await selector.select();
    expect(calls, 2);
  });

  test('an endpoint changed during probing is not overwritten', () async {
    final gate = Completer<void>();
    var current = NodeEndpoint.direct;
    const custom = NodeEndpoint(
        chatApi: 'https://custom.test/chat',
        imApi: 'https://custom.test/api',
        imWs: 'wss://custom.test/ws');
    final selector = StartupNodeSelector(
        readCurrent: () => current,
        apply: (_) async => fail('Stale selection was persisted'),
        probe: (node) async {
          await gate.future;
          return result(node, true);
        });
    final pending = selector.select();
    current = custom;
    gate.complete();
    expect((await pending).selected, custom);
  });

  test('persist stores the direct route and retains other server settings',
      () async {
    await DataSp.putServerConfig({'logLevel': '4', 'serverIP': 'custom-value'});
    await StartupNodeSelector.persist(NodeEndpoint.direct);
    expect(DataSp.getServerConfig(), {
      'authUrl': NodeEndpoint.direct.chatApi,
      'apiUrl': NodeEndpoint.direct.imApi,
      'wsUrl': NodeEndpoint.direct.imWs,
      'logLevel': '4',
      'serverIP': 'custom-value',
    });
  });

  test('unexpected probe failure does not prevent startup', () async {
    final selected = await StartupNodeSelector(
        probe: (_) async => throw StateError('unreachable')).select();
    expect(selected.selected.signature, NodeEndpoint.direct.signature);
    expect(selected.checks.single.available, isFalse);
  });
}
