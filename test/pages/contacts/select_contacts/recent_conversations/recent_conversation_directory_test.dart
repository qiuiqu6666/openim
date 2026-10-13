import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/select_contacts/recent_conversations/recent_conversation_directory.dart';

ConversationInfo group(String id) => ConversationInfo(
    conversationID: 'sg_$id',
    groupID: id,
    conversationType: ConversationType.superGroup);

void main() {
  test('failed group check preserves unrelated chats and retry recovers',
      () async {
    var fail = true;
    final source = RecentConversationDirectory((id) async {
      if (id == 'broken' && fail) throw StateError('offline');
      return id != 'left';
    });
    final rows = [
      group('broken'),
      ConversationInfo(
          conversationID: 'single',
          userID: 'peer',
          conversationType: ConversationType.single),
      group('joined'),
      group('left')
    ];
    final first =
        await source.load(rows, isVisible: (_) => true, isCurrent: () => true);
    expect(first.failed, isTrue);
    expect(
        first.rows.map((row) => row.conversationID), ['single', 'sg_joined']);
    fail = false;
    final retry =
        await source.load(rows, isVisible: (_) => true, isCurrent: () => true);
    expect(retry.failed, isFalse);
    expect(retry.rows.map((row) => row.conversationID),
        ['sg_broken', 'single', 'sg_joined']);
  });

  test('membership checks have bounded concurrency and retain SDK ordering',
      () async {
    final pending = <Completer<bool>>[];
    var active = 0, peak = 0;
    final source = RecentConversationDirectory((_) async {
      active++;
      if (active > peak) peak = active;
      final reply = Completer<bool>();
      pending.add(reply);
      try {
        return await reply.future;
      } finally {
        active--;
      }
    });
    final reading = source.load(List.generate(12, (index) => group('$index')),
        isVisible: (_) => true, isCurrent: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(4));
    for (var batch = 0; batch < 3; batch++) {
      for (final reply
          in pending.where((reply) => !reply.isCompleted).toList()) {
        reply.complete(true);
      }
      await Future<void>.delayed(Duration.zero);
    }
    final result = await reading;
    expect(peak, 4);
    expect(result.rows.map((row) => row.groupID),
        List.generate(12, (index) => '$index'));
  });

  test(
      'a replaced session stops pending checks from publishing or starting more',
      () async {
    var current = true, calls = 0;
    final reply = Completer<bool>();
    final source = RecentConversationDirectory((_) {
      calls++;
      return reply.future;
    });
    final reading = source.load(List.generate(8, (index) => group('$index')),
        isVisible: (_) => true, isCurrent: () => current);
    current = false;
    reply.complete(true);
    final result = await reading;
    expect(calls, 4);
    expect(result.rows, isEmpty);
  });
}
