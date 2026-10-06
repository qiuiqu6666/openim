import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/data/data.dart';

void main() {
  const config = CustomerServiceConfig(
      baseUrl: 'https://support.example/kefu', inboxIdentifier: 'inbox');

  test(
      'subscribes to RoomChannel and filters messages and typing by conversation',
      () async {
    final transport = _Transport();
    final received = <CustomerServiceMessage>[];
    final typing = <bool>[];
    var confirmations = 0;
    final cable = CustomerServiceCable(
        config: config,
        transport: transport,
        onMessage: received.add,
        onTyping: typing.add,
        onConnected: () => confirmations++);
    cable.connect(pubsubToken: 'public-room-token', conversationId: '42');
    await _flush();
    final connection = transport.connections.single;
    expect(
        transport.uris.single.toString(), 'wss://support.example/kefu/cable');
    final subscribe = jsonDecode(connection.sent.single) as Map;
    expect(subscribe['command'], 'subscribe');
    expect(jsonDecode(subscribe['identifier'] as String), {
      'channel': 'RoomChannel',
      'pubsub_token': 'public-room-token',
    });
    connection.add({'type': 'confirm_subscription'});
    connection.add({'type': 'confirm_subscription'});
    connection.add({'type': 'ping'});
    connection.add('not valid JSON');
    connection.event('message.created', {
      'id': 1,
      'conversation_id': 41,
      'content': 'Wrong conversation',
    });
    connection.event('message.created', {
      'id': 2,
      'conversation_id': 42,
      'content': 'Current conversation',
    });
    connection.event('message.updated', {
      'id': 2,
      'conversation': {'id': 42},
      'content': 'Edited reply',
    });
    connection.event('conversation_typing_on', {'id': 41});
    connection.event('conversation_typing_on', {
      'conversation': {'id': 42}
    });
    connection.event('conversation_typing_off', {'id': 42});
    connection.event('conversation_typing_on', {});
    expect(confirmations, 1);
    expect(received.map((message) => message.content),
        ['Current conversation', 'Edited reply']);
    expect(typing, [true, false]);
    cable.dispose();
    await _flush();
    expect(connection.closed, isTrue);
  });

  test(
      'suspension drops frames and resume subscribes with the new conversation',
      () async {
    final transport = _Transport();
    final received = <CustomerServiceMessage>[];
    final cable = CustomerServiceCable(
        config: config,
        transport: transport,
        onMessage: received.add,
        onTyping: (_) {});
    cable.connect(pubsubToken: 'token', conversationId: 'old');
    await _flush();
    final old = transport.connections.single;
    cable.suspend();
    old.event('message.created',
        {'id': 1, 'conversation_id': 'old', 'content': 'late'});
    await _flush();
    expect(old.closed, isTrue);
    expect(received, isEmpty);
    cable.connect(pubsubToken: 'token', conversationId: 'new');
    await _flush();
    final current = transport.connections.last;
    current.event('message.created',
        {'id': 2, 'conversation_id': 'old', 'content': 'wrong'});
    current.event('message.created',
        {'id': 3, 'conversation_id': 'new', 'content': 'correct'});
    expect(received.single.content, 'correct');
    cable.dispose();
    await _flush();
    cable.connect(pubsubToken: 'token', conversationId: 'new');
    await _flush();
    expect(transport.connections, hasLength(2));
  });

  test('pending native connection is closed when page is disposed', () async {
    final transport = _Transport()
      ..gate = Completer<CustomerServiceConnection>();
    final cable = CustomerServiceCable(
        config: config,
        transport: transport,
        onMessage: (_) => fail('disposed page received a message'),
        onTyping: (_) {});
    cable.connect(pubsubToken: 'token', conversationId: '42');
    await _flush();
    cable.dispose();
    final late = _Connection();
    transport.gate!.complete(late);
    await _flush();
    expect(late.closed, isTrue);
    expect(late.sent, isEmpty);
  });

  testWidgets('reconnect backs off and disposal cancels the pending retry',
      (tester) async {
    final transport = _Transport()..failures = 2;
    final cable = CustomerServiceCable(
        config: config,
        transport: transport,
        onMessage: (_) {},
        onTyping: (_) {});
    cable.connect(pubsubToken: 'token', conversationId: '42');
    await tester.pump();
    expect(transport.uris, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.uris, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.uris, hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    expect(transport.uris, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.connections, hasLength(1));
    transport.connections.single.add({'type': 'confirm_subscription'});
    await transport.connections.single.controller.close();
    await tester.pump();
    cable.dispose();
    await tester.pump(const Duration(seconds: 40));
    expect(transport.uris, hasLength(3));
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Transport implements CustomerServiceTransport {
  final uris = <Uri>[];
  final connections = <_Connection>[];
  int failures = 0;
  Completer<CustomerServiceConnection>? gate;

  @override
  Future<CustomerServiceConnection> connect(Uri uri) async {
    uris.add(uri);
    if (failures > 0) {
      failures--;
      throw StateError('offline');
    }
    if (gate != null) return gate!.future;
    final connection = _Connection();
    connections.add(connection);
    return connection;
  }
}

class _Connection implements CustomerServiceConnection {
  final controller = StreamController<dynamic>.broadcast(sync: true);
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get messages => controller.stream;
  @override
  void send(String message) => sent.add(message);
  void add(dynamic raw) {
    if (!controller.isClosed) {
      controller.add(raw is String ? raw : jsonEncode(raw));
    }
  }

  void event(String name, Map<String, dynamic> data) => add({
        'message': {'event': name, 'data': data}
      });

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }
}
