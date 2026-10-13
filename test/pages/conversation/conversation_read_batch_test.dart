import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/conversation/editing/conversation_read_batch.dart';

void main() {
  List<ConversationInfo> rows(int count) => List.generate(
      count, (i) => ConversationInfo(conversationID: '$i', unreadCount: 1));
  test(
      '3000 conversations are deduplicated, bounded and failure does not stop batch',
      () async {
    final attempts = <String, int>{};
    var active = 0, peak = 0, completed = 0;
    final data = rows(3000);
    final failed = await runConversationReadBatch(
      conversations: [
        ...data,
        data.first,
        ConversationInfo(conversationID: 'read', unreadCount: 0)
      ],
      isCurrent: () => true,
      markRead: (c) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration.zero);
        active--;
        final attempt =
            attempts.update(c.conversationID, (v) => v + 1, ifAbsent: () => 1);
        if (c.conversationID == '8' ||
            (c.conversationID == '4' && attempt == 1))
          throw StateError('offline');
      },
      progress: (done, total) {
        completed = done;
        expect(total, 3000);
      },
    );
    expect(failed, 1);
    expect(completed, 3000);
    expect(peak, lessThanOrEqualTo(3));
    expect(attempts['4'], 2);
    expect(attempts['2999'], 1);
  });
  test('timeouts retire workers without retrying native requests', () async {
    var calls = 0;
    final failed = await runConversationReadBatch(
        conversations: rows(20),
        isCurrent: () => true,
        markRead: (_) async {
          calls++;
          throw TimeoutException('pending');
        },
        progress: (_, __) {});
    expect(calls, 3);
    expect(failed, 20);
  });
  test('account change stops subsequent work', () async {
    var current = true, calls = 0;
    await runConversationReadBatch(
        conversations: rows(20),
        isCurrent: () => current,
        markRead: (_) async {
          calls++;
          current = false;
        },
        progress: (_, __) {});
    expect(calls, 1);
  });
}
