import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/receipts/conversation_read_coordinator.dart';

void main() {
  test('visible messages share a read request; newer arrivals get another',
      () async {
    final reads = ConversationReadCoordinator();
    final first = Completer<void>();
    var calls = 0;
    Future<void> send() {
      calls++;
      return calls == 1 ? first.future : Future.value();
    }

    final a = reads.markRead(26, send);
    final b = reads.markRead(25, send);
    final c = reads.markRead(27, send);
    expect(calls, 1);
    first.complete();
    await Future.wait([a, b, c]);
    expect(calls, 2);
    await reads.markRead(26, send);
    expect(calls, 2);
  });
  test('failed requests can retry', () async {
    final reads = ConversationReadCoordinator();
    await expectLater(
        reads.markRead(26, () => Future.error(StateError('offline'))),
        throwsStateError);
    var calls = 0;
    await reads.markRead(26, () async {
      calls++;
    });
    expect(calls, 1);
  });

  test(
      'different unsequenced arrivals require another read after the pending request',
      () async {
    final reads = ConversationReadCoordinator();
    final first = Completer<void>();
    var calls = 0;
    Future<void> send() {
      calls++;
      return calls == 1 ? first.future : Future.value();
    }

    final a = reads.markRead(0, send, messageID: 'arrival-a');
    final b = reads.markRead(0, send, messageID: 'arrival-b');
    expect(calls, 1);
    first.complete();
    await Future.wait([a, b]);
    expect(calls, 2);
  });

  test(
      'repeated visibility of the same unsequenced latest message shares one read',
      () async {
    final reads = ConversationReadCoordinator();
    final first = Completer<void>();
    var calls = 0;
    Future<void> send() {
      calls++;
      return first.future;
    }

    final a = reads.markRead(0, send, messageID: 'same-latest');
    final b = reads.markRead(0, send, messageID: 'same-latest');
    first.complete();
    await Future.wait([a, b]);
    await reads.markRead(0, send, messageID: 'same-latest');
    expect(calls, 1);
  });

  test(
      'new identity is read even when a mixed timeline retains the same known seq',
      () async {
    final reads = ConversationReadCoordinator();
    final first = Completer<void>();
    var calls = 0;
    Future<void> send() {
      calls++;
      return calls == 1 ? first.future : Future.value();
    }

    final a = reads.markRead(10, send, messageID: 'known-seq');
    final b = reads.markRead(10, send, messageID: 'new-without-seq');
    first.complete();
    await Future.wait([a, b]);
    expect(calls, 2);
  });

  test(
      'a newly observed unread revision retries an already read latest message',
      () async {
    final reads = ConversationReadCoordinator();
    var calls = 0;
    Future<void> send() async => calls++;

    await reads.markRead(10, send, messageID: 'same-latest');
    await reads.markRead(10, send, messageID: 'same-latest');
    expect(calls, 1);
    await reads.markRead(10, send, messageID: 'same-latest', revision: 1);
    await reads.markRead(10, send, messageID: 'same-latest', revision: 1);
    expect(calls, 2);
  });

  test(
      'failed identity and unread revision are not cached as successfully read',
      () async {
    final reads = ConversationReadCoordinator();
    await expectLater(
        reads.markRead(10, () => Future.error(StateError('offline')),
            messageID: 'latest', revision: 2),
        throwsStateError);
    var calls = 0;
    await reads.markRead(10, () async => calls++,
        messageID: 'latest', revision: 2);
    expect(calls, 1);
  });
}
