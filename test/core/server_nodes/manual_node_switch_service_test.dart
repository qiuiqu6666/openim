import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/manual_node_switch_service.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';

void main() {
  late NodeEndpoint current;
  late Object? session;
  late bool available, allowed, active, failTarget, failRecovery;
  late List<NodeEndpoint> connections;
  Completer<void>? gate;
  late ManualNodeSwitchService service;
  setUp(() {
    current = NodeEndpoint.direct;
    session = 'account';
    available = allowed = active = true;
    failTarget = failRecovery = false;
    gate = null;
    connections = [];
    service = ManualNodeSwitchService(
      readSession: () => session,
      readEndpoint: () => current,
      canSwitch: () => allowed,
      probe: (node) async {
        await gate?.future;
        return NodeAvailability(node, available: available, latencyMs: 10);
      },
      connect: (node, sameSession) async {
        expect(sameSession(), isTrue);
        connections.add(node);
        current = node;
        if ((connections.length == 1 && failTarget) ||
            (connections.length > 1 && failRecovery)) {
          throw StateError('connection failed');
        }
      },
    );
  });
  Future<void> change() =>
      service.switchTo(NodeEndpoint.direct, isActive: () => active);

  test('preflights then reconnects all endpoint addresses', () async {
    await change();
    expect(current, NodeEndpoint.direct);
    expect(connections, [NodeEndpoint.direct]);
    expect(service.busy, isFalse);
  });
  test('unavailable target does not disconnect original', () async {
    available = false;
    await expectLater(change(), throwsA(NodeSwitchFailure.unavailable));
    expect(connections, isEmpty);
    expect(current, NodeEndpoint.direct);
  });
  test('failed target reconnect restores previous route', () async {
    failTarget = true;
    await expectLater(change(), throwsA(NodeSwitchFailure.connectionFailed));
    expect(connections, [NodeEndpoint.direct, NodeEndpoint.direct]);
    expect(current, NodeEndpoint.direct);
  });
  test('failed rollback is not reported as restored', () async {
    failTarget = failRecovery = true;
    await expectLater(change(), throwsA(NodeSwitchFailure.recoveryFailed));
    expect(service.busy, isFalse);
  });
  test('duplicate switch cannot race native reconnect', () async {
    gate = Completer<void>();
    final first = change();
    await expectLater(change(), throwsA(NodeSwitchFailure.busy));
    gate!.complete();
    await first;
    expect(connections, hasLength(1));
  });
  for (final reason in ['account', 'background', 'call']) {
    test('$reason changed during probe prevents disconnect', () async {
      gate = Completer<void>();
      final first = change();
      final expected = expectLater(
          first,
          throwsA(reason == 'call'
              ? NodeSwitchFailure.busy
              : NodeSwitchFailure.sessionChanged));
      if (reason == 'account') session = 'new account';
      if (reason == 'background') active = false;
      if (reason == 'call') allowed = false;
      gate!.complete();
      await expected;
      expect(connections, isEmpty);
    });
  }
  test('account replacement during reconnect never restores old account',
      () async {
    service = ManualNodeSwitchService(
      readSession: () => session,
      readEndpoint: () => current,
      canSwitch: () => true,
      probe: (node) async =>
          NodeAvailability(node, available: true, latencyMs: 1),
      connect: (node, _) async {
        connections.add(node);
        session = null;
        throw StateError('logged out');
      },
    );
    await expectLater(change(), throwsA(NodeSwitchFailure.sessionChanged));
    expect(connections, [NodeEndpoint.direct]);
  });
  test('automatic shield route uses the same serialized switch flow', () async {
    await service.switchTo(NodeEndpoint.shield,
        isActive: () => active, allowShield: true);
    expect(current, NodeEndpoint.shield);
  });
  test('automatic shield cannot replace a custom deployment', () async {
    current = const NodeEndpoint(
        chatApi: 'https://custom.test',
        imApi: 'https://custom.test/api',
        imWs: 'wss://custom.test/ws');
    await expectLater(
        service.switchTo(NodeEndpoint.shield,
            isActive: () => active, allowShield: true),
        throwsA(NodeSwitchFailure.unavailable));
    expect(connections, isEmpty);
  });
  test('custom deployment does not switch into production', () async {
    current = const NodeEndpoint(
        chatApi: 'https://custom.example',
        imApi: 'https://custom.example/im',
        imWs: 'wss://custom.example');
    await expectLater(change(), throwsA(NodeSwitchFailure.unavailable));
    expect(connections, isEmpty);
  });
  test('shield loopback cannot be selected manually', () async {
    const removed = NodeEndpoint(
        chatApi: 'http://127.0.0.1:10008',
        imApi: 'http://127.0.0.1:10002',
        imWs: 'ws://127.0.0.1:10001');
    await expectLater(service.switchTo(removed, isActive: () => active),
        throwsA(NodeSwitchFailure.unavailable));
    expect(connections, isEmpty);
    expect(current, NodeEndpoint.direct);
  });
}
