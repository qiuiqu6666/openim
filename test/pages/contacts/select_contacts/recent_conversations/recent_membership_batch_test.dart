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
  test('thousands of rows use one bulk call; send still checks fresh',
      () async {
    var bulkCalls = 0;
    var individualCalls = 0;
    final directory = RecentConversationDirectory((_) async {
      individualCalls++;
      return false;
    }, joinedGroupIDs: () async {
      bulkCalls++;
      return {'1', '2500'};
    });
    final cache = RecentMembershipCache();
    final result = await directory.load(List.generate(3000, (i) => group('$i')),
        isVisible: (_) => true, isCurrent: () => true, cache: cache);
    expect(bulkCalls, 1);
    expect(individualCalls, 0);
    expect(result.rows.map((r) => r.groupID), ['1', '2500']);
    expect(
        await directory
            .validateForSend(['1'], isCurrent: () => true, cache: cache),
        isFalse);
    expect(individualCalls, 1);
  });

  test('bulk failure retains known groups without per-row fallback', () async {
    final cache = RecentMembershipCache();
    cache.complete('known', cache.begin('known'), true);
    final directory = RecentConversationDirectory(
        (_) async => throw StateError('must not call'),
        joinedGroupIDs: () async => throw StateError('offline'));
    final result = await directory.load([group('known'), group('unknown')],
        isVisible: (_) => true, isCurrent: () => true, cache: cache);
    expect(result.failed, isTrue);
    expect(result.rows.single.groupID, 'known');
  });

  test('older bulk snapshot cannot override a newer send rejection', () async {
    final reply = Completer<Set<String>>();
    final cache = RecentMembershipCache();
    final directory = RecentConversationDirectory((_) async => false,
        joinedGroupIDs: () => reply.future);
    final loading = directory.load([group('left')],
        isVisible: (_) => true, isCurrent: () => true, cache: cache);
    await directory
        .validateForSend(['left'], isCurrent: () => true, cache: cache);
    reply.complete({'left'});
    expect((await loading).rows, isEmpty);
  });

  test('closed session cannot publish late bulk results', () async {
    var current = true;
    final reply = Completer<Set<String>>();
    final cache = RecentMembershipCache();
    final directory = RecentConversationDirectory((_) async => true,
        joinedGroupIDs: () => reply.future);
    final loading = directory.load([group('group')],
        isVisible: (_) => true, isCurrent: () => current, cache: cache);
    current = false;
    reply.complete({'group'});
    expect((await loading).rows, isEmpty);
    expect(cache.contains('group'), isFalse);
  });
}
