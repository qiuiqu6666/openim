import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/blacklist/conversation_blacklist_visibility.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/summary/conversation_feed_snapshot.dart';

ConversationInfo row(String id, int time, {bool pinned = false}) =>
    ConversationInfo.fromJson({
      'conversationID': 'single_$id',
      'userID': id,
      'conversationType': ConversationType.single,
      'latestMsgSendTime': time,
      'isPinned': pinned,
      'unreadCount': 0,
      'draftText': 'draft $id',
      'draftTextTime': time,
    });

void main() {
  test('unblock restores the same position, pin and draft without SDK mutation',
      () {
    final rows = [
      row('pinned', 1, pinned: true),
      row('a', 30),
      row('b', 20),
      row('c', 10)
    ].obs;
    final before = rows.map((e) => e.toJson()).toList();
    final visibility = ConversationBlacklistVisibility(
        load: () async => [], isActive: () => true, changed: rows.refresh);
    final cache = ConversationFeedSnapshotCache(
        rows, <String, ChatConversationState>{}.obs,
        allows: visibility.allows);
    addTearDown(cache.dispose);
    expect(
        cache.read().singles.map((e) => e.userID), ['pinned', 'a', 'b', 'c']);
    visibility.setBlocked('b', true);
    visibility.setBlocked('pinned', true);
    expect(cache.read().singles.map((e) => e.userID), ['a', 'c']);
    visibility.setBlocked('b', false);
    visibility.setBlocked('pinned', false);
    expect(
        cache.read().singles.map((e) => e.userID), ['pinned', 'a', 'b', 'c']);
    expect(rows.map((e) => e.toJson()).toList(), before);
  });

  test('restart and blacklist-page events reload visibility from SDK',
      () async {
    var blocked = [
      BlacklistInfo.fromJson({'blockUserID': 'b'})
    ];
    final visibility = ConversationBlacklistVisibility(
        load: () async => blocked, isActive: () => true, changed: () {});
    await visibility.refresh();
    expect(visibility.allows(row('b', 20)), isFalse);
    blocked = [];
    await visibility.refresh();
    expect(visibility.allows(row('b', 20)), isTrue);
  });

  test('stale loading cannot undo a confirmed unblock or changed session',
      () async {
    var active = true;
    var changes = 0;
    final pending = Completer<List<BlacklistInfo>>();
    final visibility = ConversationBlacklistVisibility(
        load: () => pending.future,
        isActive: () => active,
        changed: () => changes++);
    visibility.setBlocked('b', true);
    final request = visibility.refresh();
    visibility.setBlocked('b', false);
    pending.complete([
      BlacklistInfo.fromJson({'blockUserID': 'b'})
    ]);
    await request;
    expect(visibility.allows(row('b', 20)), isTrue);
    final previous = changes;
    active = false;
    await visibility.refresh();
    expect(changes, previous);
  });
}
