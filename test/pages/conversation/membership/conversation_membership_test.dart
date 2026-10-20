import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/membership/conversation_membership.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/summary/conversation_feed_snapshot.dart';

ConversationInfo group(String id) => ConversationInfo(
    conversationID: 'sg_$id', conversationType: 3, groupID: id, unreadCount: 4);

void main() {
  test('complete paginated membership filters groups and badges', () async {
    final membership = ConversationMembership(
      isActive: () => true,
      fetchPage: (offset, count) async => offset == 0
          ? List.generate(count, (i) => GroupInfo(groupID: '$i'))
          : [GroupInfo(groupID: 'last')],
    );
    final cache = ConversationFeedSnapshotCache(
      [group('last'), group('left')].obs,
      <String, ChatConversationState>{}.obs,
      allows: membership.allows,
      membershipRevision: membership.revision,
    );
    expect(cache.read().groups.length, 2);
    await membership.refresh();
    expect(cache.read().groups.single.groupID, 'last');
    expect(cache.read().groupUnread, 4);
    membership.changed('last', false);
    expect(cache.read().groups, isEmpty);
    expect(cache.read().groupUnread, 0);
    membership.changed('last', true);
    expect(cache.read().groups.length, 1);
    cache.dispose();
  });

  test('callbacks during reads win, including repeated leave and rejoin',
      () async {
    final response = Completer<List<GroupInfo>>();
    final membership = ConversationMembership(
        isActive: () => true, fetchPage: (_, __) => response.future);
    membership.changed('left', false);
    final pending = membership.refresh();
    expect(membership.allows(group('left')), isFalse);
    membership.changed('left', false);
    membership.changed('new', true);
    response.complete([GroupInfo(groupID: 'left')]);
    await pending;
    expect(membership.allows(group('left')), isFalse);
    expect(membership.allows(group('new')), isTrue);
  });

  test('failed refresh retains known membership and explicit removals',
      () async {
    var fail = false;
    final membership = ConversationMembership(
      isActive: () => true,
      fetchPage: (_, __) async {
        if (fail) throw StateError('offline');
        return [GroupInfo(groupID: 'joined')];
      },
    );
    await membership.refresh();
    membership.changed('joined', false);
    fail = true;
    await membership.refresh();
    expect(membership.allows(group('joined')), isFalse);
    expect(membership.allows(group('other')), isFalse);
    expect(
        membership.allows(
            ConversationInfo(conversationID: 'single', conversationType: 1)),
        isTrue);
  });

  test('late results from a closed session are ignored', () async {
    var active = true;
    final response = Completer<List<GroupInfo>>();
    final membership = ConversationMembership(
        isActive: () => active, fetchPage: (_, __) => response.future);
    final pending = membership.refresh();
    active = false;
    response.complete([]);
    await pending;
    expect(membership.revision.value, 0);
  });
}
