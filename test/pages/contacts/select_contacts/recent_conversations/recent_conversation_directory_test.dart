import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/select_contacts/recent_conversations/recent_conversation_directory.dart';
import 'package:openim/pages/contacts/select_contacts/recent_conversations/recent_membership_cache.dart';

ConversationInfo group(String id) => ConversationInfo(
    conversationID: 'sg_$id',
    groupID: id,
    conversationType: ConversationType.superGroup);

void main() {
  test('cached groups and singles publish before blocked SDK checks', () async {
    final cache = RecentMembershipCache();
    cache.complete('cached', cache.begin('cached'), true);
    final pending = <String, Completer<bool>>{};
    final source = RecentConversationDirectory(
        (id) => (pending[id] = Completer<bool>()).future);
    final updates = <List<String?>>[];
    final reading = source.load([
      group('slow'),
      group('cached'),
      ConversationInfo(
          conversationID: 'single', conversationType: ConversationType.single),
      group('fast'),
    ],
        isVisible: (_) => true,
        isCurrent: () => true,
        cache: cache,
        onUpdate: (rows) =>
            updates.add(rows.map((r) => r.conversationID).toList()));
    expect(updates.single, ['sg_cached', 'single']);
    pending['fast']!.complete(true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(updates.last, ['sg_cached', 'single', 'sg_fast']);
    pending['cached']!.complete(false);
    pending['slow']!.complete(true);
    final result = await reading;
    expect(result.rows.map((r) => r.conversationID),
        ['sg_slow', 'single', 'sg_fast']);
    expect(cache.contains('cached'), isFalse);
  });

  test('reopened picker reuses evidence only for same owner and login',
      () async {
    final owner = Object();
    final cache = RecentMembershipCache.forSession(owner, 'self', 'token');
    final source = RecentConversationDirectory((_) async => true);
    await source.load([group('joined')],
        isVisible: (_) => true, isCurrent: () => true, cache: cache);
    expect(
        RecentMembershipCache.forSession(owner, 'self', 'token'), same(cache));
    expect(
        RecentMembershipCache.forSession(Object(), 'self', 'token')
            .contains('joined'),
        isFalse);
    expect(
        RecentMembershipCache.forSession(owner, 'other', 'token')
            .contains('joined'),
        isFalse);
    expect(
        RecentMembershipCache.forSession(owner, 'self', 'new-token')
            .contains('joined'),
        isFalse);
  });

  test('send always rechecks cached groups and rejects departed groups',
      () async {
    final cache = RecentMembershipCache();
    cache.complete('left', cache.begin('left'), true);
    final calls = <String>[];
    final excluded = <String>[];
    final source = RecentConversationDirectory((id) async {
      calls.add(id);
      return false;
    });
    expect(
        await source.validateForSend(['left', 'left'],
            isCurrent: () => true, cache: cache, onExcluded: excluded.add),
        isFalse);
    expect(calls, ['left']);
    expect(excluded, ['left']);
    expect(cache.contains('left'), isFalse);
  });

  test('send fails closed on errors and obsolete sessions', () async {
    final cache = RecentMembershipCache();
    final broken =
        RecentConversationDirectory((_) async => throw StateError('offline'));
    expect(
        await broken
            .validateForSend(['group'], isCurrent: () => true, cache: cache),
        isFalse);
    var current = true;
    final reply = Completer<bool>();
    final source = RecentConversationDirectory((_) => reply.future);
    final sending = source
        .validateForSend(['group'], isCurrent: () => current, cache: cache);
    current = false;
    reply.complete(true);
    expect(await sending, isFalse);
    expect(cache.contains('group'), isFalse);
  });

  testWidgets('send timeout never approves a cached group', (tester) async {
    final cache = RecentMembershipCache();
    cache.complete('group', cache.begin('group'), true);
    final reply = Completer<bool>();
    final source = RecentConversationDirectory((_) => reply.future);
    final sending =
        source.validateForSend(['group'], isCurrent: () => true, cache: cache);
    await tester.pump(const Duration(seconds: 5));
    expect(await sending, isFalse);
    reply.complete(true);
    await tester.pump();
  });

  test('late display check cannot restore a send-time rejected group',
      () async {
    final cache = RecentMembershipCache();
    final old = Completer<bool>();
    var calls = 0;
    final source = RecentConversationDirectory(
        (_) => ++calls == 1 ? old.future : Future.value(false));
    final reading = source.load([group('left')],
        isVisible: (_) => true, isCurrent: () => true, cache: cache);
    expect(
        await source
            .validateForSend(['left'], isCurrent: () => true, cache: cache),
        isFalse);
    old.complete(true);
    expect((await reading).rows, isEmpty);
    expect(cache.contains('left'), isFalse);
  });

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
