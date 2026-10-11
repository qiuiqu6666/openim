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

  test('falls back as one route and preserves other settings and credentials',
      () async {
    await DataSp.putServerConfig({'logLevel': '4'});
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'u',
      'imToken': 'im-secret',
      'chatToken': 'chat-secret',
    }));
    final selected = await StartupNodeSelector(
            probe: (node) async => result(node, node == NodeEndpoint.direct))
        .select();
    expect(selected.selected, NodeEndpoint.direct);
    expect(NodeEndpoint.current().signature, NodeEndpoint.direct.signature);
    expect(DataSp.getServerConfig()?['logLevel'], '4');
    expect(DataSp.imToken, 'im-secret');
    expect(DataSp.chatToken, 'chat-secret');
  });

  test('each launch rechecks and returns to the secure domain when restored',
      () async {
    await StartupNodeSelector(
            probe: (node) async => result(node, node == NodeEndpoint.direct))
        .select();
    final probed = <NodeEndpoint>[];
    final selected = await StartupNodeSelector(probe: (node) async {
      probed.add(node);
      return result(node, true);
    }).select();
    expect(probed, NodeEndpoint.builtIn);
    expect(selected.selected, NodeEndpoint.primary);
    expect(NodeEndpoint.current().signature, NodeEndpoint.primary.signature);
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
    expect(calls, 2);
    gate.complete();
    await first;
    await selector.select();
    expect(calls, 4);
  });

  test('an endpoint changed during probing is not overwritten', () async {
    final gate = Completer<void>();
    var current = NodeEndpoint.primary;
    final selector = StartupNodeSelector(
        readCurrent: () => current,
        apply: (_) async => fail('Stale selection was persisted'),
        probe: (node) async {
          await gate.future;
          return result(node, true);
        });
    final pending = selector.select();
    current = NodeEndpoint.direct;
    gate.complete();
    expect((await pending).selected, NodeEndpoint.direct);
  });

  test('failed persistence retains the effective current endpoint', () async {
    final selected = await StartupNodeSelector(
            readCurrent: () => NodeEndpoint.primary,
            apply: (_) async => throw StateError('disk unavailable'),
            probe: (node) async => result(node, node == NodeEndpoint.direct))
        .select();
    expect(selected.selected, NodeEndpoint.primary);
  });

  test('unexpected probe failure does not prevent another node from working',
      () async {
    final selected = await StartupNodeSelector(probe: (node) async {
      if (node == NodeEndpoint.primary) throw StateError('unreachable');
      return result(node, true);
    }).select();
    expect(selected.selected, NodeEndpoint.direct);
  });
}
