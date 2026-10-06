import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';

Message _message(int status, {int seq = 0}) => Message(
      clientMsgID: 'outgoing',
      contentType: MessageType.text,
      sendID: 'self',
      recvID: 'peer',
      createTime: 10,
      sendTime: seq == 0 ? 10 : 20,
      seq: seq,
      serverMsgID: seq == 0 ? null : 'server-$seq',
      status: status,
      isRead: false,
    );

class _History {
  _History(Message local) {
    messages.add(local);
    loader = ChatHistoryLoader(
      fetch: ({required count, startMsg}) => query.future,
      messages: () => messages,
      replace: (next, _, __) => messages.assignAll(next),
      removedIDs: {},
      onStateChanged: () {},
    );
  }

  final query = Completer<AdvancedMessage>();
  final messages = <Message>[].obs;
  late final ChatHistoryLoader loader;

  void complete(List<Message> page) {
    query.complete(AdvancedMessage(messageList: page, isEnd: true));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final staleStatus in [MessageStatus.sending, MessageStatus.failed]) {
    test('success received during history rejects stale status $staleStatus',
        () async {
      final local = _message(MessageStatus.sending);
      final h = _History(local);
      addTearDown(h.loader.close);
      final loading = h.loader.refresh();
      local.update(_message(MessageStatus.succeeded, seq: 7));
      h.complete([_message(staleStatus)]);
      await loading;

      expect(h.messages.single, same(local));
      expect(local.status, MessageStatus.succeeded);
      expect(local.seq, 7);
      expect(local.serverMsgID, 'server-7');
      expect(local.sendTime, 20);
    });

    test('previously acknowledged message rejects stale status $staleStatus',
        () async {
      final local = _message(MessageStatus.succeeded, seq: 7);
      final h = _History(local);
      addTearDown(h.loader.close);
      final loading = h.loader.loadOlder();
      h.complete([_message(staleStatus)]);
      await loading;

      expect(h.messages.single, same(local));
      expect(local.status, MessageStatus.succeeded);
      expect(local.serverMsgID, 'server-7');
    });
  }

  test('failure received during history is not reset to sending', () async {
    final local = _message(MessageStatus.sending);
    final h = _History(local);
    addTearDown(h.loader.close);
    final loading = h.loader.refresh();
    local.status = MessageStatus.failed;
    h.complete([_message(MessageStatus.sending)]);
    await loading;

    expect(h.messages.single, same(local));
    expect(local.status, MessageStatus.failed);
  });

  test('retry started during history is not reset to the prior failure',
      () async {
    final local = _message(MessageStatus.failed);
    final h = _History(local);
    addTearDown(h.loader.close);
    final loading = h.loader.refresh();
    local.status = MessageStatus.sending;
    h.complete([_message(MessageStatus.failed)]);
    await loading;

    expect(h.messages.single, same(local));
    expect(local.status, MessageStatus.sending);
  });

  test('acknowledgement received during an empty history page stays visible',
      () async {
    final local = _message(MessageStatus.sending);
    final h = _History(local);
    addTearDown(h.loader.close);
    final loading = h.loader.loadOlder();
    local.update(_message(MessageStatus.succeeded, seq: 7));
    h.complete([]);
    await loading;

    expect(h.messages.single, same(local));
    expect(local.status, MessageStatus.succeeded);
  });

  for (final previous in [MessageStatus.sending, MessageStatus.failed]) {
    test('SDK success remains authoritative over local status $previous',
        () async {
      final local = _message(previous);
      final h = _History(local);
      addTearDown(h.loader.close);
      final loading = h.loader.loadOlder();
      h.complete([_message(MessageStatus.succeeded, seq: 8)]);
      await loading;

      expect(h.messages.single, same(local));
      expect(local.status, MessageStatus.succeeded);
      expect(local.seq, 8);
      expect(local.serverMsgID, 'server-8');
    });
  }

  test('SDK success can confirm a failure received during the query', () async {
    final local = _message(MessageStatus.sending);
    final h = _History(local);
    addTearDown(h.loader.close);
    final loading = h.loader.refresh();
    local.status = MessageStatus.failed;
    h.complete([_message(MessageStatus.succeeded, seq: 8)]);
    await loading;

    expect(h.messages.single, same(local));
    expect(local.status, MessageStatus.succeeded);
    expect(local.seq, 8);
  });

  test('unchanged local state accepts SDK retry or failure state', () async {
    for (final states in [
      (MessageStatus.failed, MessageStatus.sending),
      (MessageStatus.sending, MessageStatus.failed),
    ]) {
      final local = _message(states.$1);
      final h = _History(local);
      addTearDown(h.loader.close);
      final loading = h.loader.refresh();
      h.complete([_message(states.$2)]);
      await loading;

      expect(h.messages.single, same(local));
      expect(local.status, states.$2);
    }
  });

  test('confirmed SDK metadata still updates after a concurrent send receipt',
      () async {
    final local = _message(MessageStatus.sending);
    final h = _History(local);
    addTearDown(h.loader.close);
    final loading = h.loader.refresh();
    local.update(_message(MessageStatus.succeeded, seq: 7));
    h.complete([_message(MessageStatus.succeeded, seq: 8)]);
    await loading;

    expect(h.messages.single, same(local));
    expect(local.seq, 8);
    expect(local.serverMsgID, 'server-8');
  });

  test('rejecting a stale send state preserves concurrent read and localEx',
      () async {
    final local = _message(MessageStatus.sending)..localEx = 'old';
    final h = _History(local);
    addTearDown(h.loader.close);
    final loading = h.loader.refresh();
    local.update(_message(MessageStatus.succeeded, seq: 7));
    local.isRead = true;
    local.hasReadTime = 100;
    local.localEx = 'voice-heard';
    h.complete([_message(MessageStatus.sending)..localEx = 'old']);
    await loading;

    expect(h.messages.single, same(local));
    expect(local.isRead, isTrue);
    expect(local.hasReadTime, 100);
    expect(local.localEx, 'voice-heard');
    expect(local.seq, 7);
  });

  test('a stale send state still accepts independent SDK read and localEx',
      () async {
    final local = _message(MessageStatus.succeeded, seq: 7)..localEx = 'old';
    final h = _History(local);
    addTearDown(h.loader.close);
    final loading = h.loader.refresh();
    h.complete([
      _message(MessageStatus.sending)
        ..isRead = true
        ..hasReadTime = 101
        ..localEx = 'sdk-metadata',
    ]);
    await loading;

    expect(h.messages.single, same(local));
    expect(local.status, MessageStatus.succeeded);
    expect(local.isRead, isTrue);
    expect(local.hasReadTime, 101);
    expect(local.localEx, 'sdk-metadata');
    expect(local.seq, 7);
  });

  for (final succeeded in [true, false]) {
    test(
        'delivery ${succeeded ? 'success' : 'failure'} wins over stale history',
        () async {
      final local = _message(MessageStatus.sending);
      final h = _History(local);
      final transport = Completer<Message>();
      final delivery = ChatDeliveryController(
        messageList: h.messages,
        conversation: () =>
            ConversationInfo(conversationID: 'chat', userID: 'peer'),
        isClosed: () => false,
        groupStatus: () => null,
        scrollBottom: () {},
        resetInput: (_) {},
        accountID: 'self',
        currentAccountID: () => 'self',
        sendRaw: (_, __) => transport.future,
      );
      addTearDown(delivery.close);
      addTearDown(h.loader.close);
      final sending = delivery.send(local, addToUI: false);
      final loading = h.loader.refresh();
      if (succeeded) {
        transport.complete(_message(MessageStatus.succeeded, seq: 7));
      } else {
        transport.completeError(TimeoutException('transport'));
      }
      await sending;
      h.complete([_message(MessageStatus.sending)]);
      await loading;

      expect(h.messages.single, same(local));
      expect(local.status,
          succeeded ? MessageStatus.succeeded : MessageStatus.failed);
    });
  }
}
