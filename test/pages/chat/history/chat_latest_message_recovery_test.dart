import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_latest_message_recovery.dart';

Message latest(String id) => Message()
  ..clientMsgID = id
  ..contentType = MessageType.text
  ..status = MessageStatus.succeeded;

void main() {
  testWidgets(
      'changing targets share a budget and the final target is repaired',
      (tester) async {
    final origin = tester.binding.clock.now();
    Duration elapsed() => tester.binding.clock.now().difference(origin);
    var message = latest('0');
    final present = <String>{};
    final starts = <Duration>[];
    final recovery = ChatLatestMessageRecovery(
      elapsed: elapsed,
      isClosed: () => false,
      latestMessage: () => message,
      containsMessage: present.contains,
      isRemoved: (_) => false,
      canRefresh: () => true,
      refresh: () async {
        starts.add(elapsed());
        present.add(message.clientMsgID!);
        return true;
      },
    );
    for (var i = 0; i < 30; i++) {
      message = latest('$i');
      recovery.conversationChanged();
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(starts.length, lessThanOrEqualTo(4));
    for (var i = 1; i < starts.length; i++) {
      expect(
          starts[i] - starts[i - 1],
          greaterThanOrEqualTo(
              ChatLatestMessageRecovery.minimumRefreshInterval));
    }
    expect(present, contains('29'));
    recovery.close();
  });

  testWidgets('live arrival and covered route cancel unnecessary queued reads',
      (tester) async {
    var present = false, active = true;
    var reads = 0;
    final origin = tester.binding.clock.now();
    final recovery = ChatLatestMessageRecovery(
      elapsed: () => tester.binding.clock.now().difference(origin),
      isClosed: () => false,
      latestMessage: () => latest('m'),
      containsMessage: (_) => present,
      isRemoved: (_) => false,
      canRefresh: () => active,
      refresh: () async {
        reads++;
        return true;
      },
    );
    recovery.conversationChanged();
    present = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 0);
    present = false;
    recovery.conversationChanged();
    active = false;
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 0);
    active = true;
    recovery.conversationChanged();
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 1);
    recovery.close();
    await tester.pump(const Duration(seconds: 5));
    expect(reads, 1);
  });

  testWidgets(
      'in flight targets coalesce and same target stops after three tries',
      (tester) async {
    var message = latest('a');
    var reads = 0;
    final first = Completer<bool>();
    final origin = tester.binding.clock.now();
    final recovery = ChatLatestMessageRecovery(
      elapsed: () => tester.binding.clock.now().difference(origin),
      isClosed: () => false,
      latestMessage: () => message,
      containsMessage: (_) => false,
      isRemoved: (_) => false,
      canRefresh: () => true,
      diagnostic: (_) => throw StateError('Diagnostic sink failed'),
      refresh: () async => ++reads == 1 ? first.future : true,
    );
    recovery.conversationChanged();
    await tester.pump(const Duration(milliseconds: 100));
    message = latest('b');
    recovery.conversationChanged();
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 1);
    first.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 899));
    expect(reads, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(reads, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 4, reason: 'a once, b three times');
    recovery.close();
  });
}
