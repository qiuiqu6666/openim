import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/recent_conversation_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('scroll loads 20 at a time and retains selection ($brightness)',
        (tester) async {
      final rows = List.generate(45, (i) => recentConversation(id: '$i'));
      final fixture = RecentConversationFixture(data: rows);
      await fixture.open(tester, brightness: brightness);
      await fixture.selection.reloadRecentConversations();
      await tester.pumpAndSettle();
      expect(fixture.selection.visibleConversations, rows.take(20).toList());
      await tester.tap(recentConversationRow('0'));
      await tester.pump();
      fixture.selection.recentScrollController.jumpTo(
          fixture.selection.recentScrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(fixture.selection.visibleConversations, rows.take(40).toList());
      expect(fixture.selection.checkedList.keys, ['user-0']);
      fixture.selection.recentScrollController.jumpTo(
          fixture.selection.recentScrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(fixture.selection.visibleConversations, rows);
      expect(fixture.selection.recentHasMore.value, isFalse);
      await fixture.selection.loadMoreRecentConversations();
      expect(fixture.selection.visibleConversations, rows);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed next page retries without losing or duplicating rows',
      (tester) async {
    var fail = true;
    final rows =
        List.generate(25, (i) => recentConversation(id: '$i', group: i >= 20));
    final fixture = RecentConversationFixture(
        data: rows,
        isJoinedGroup: (_) async {
          if (fail) throw StateError('offline');
          return true;
        });
    await fixture.open(tester);
    await fixture.selection.reloadRecentConversations();
    await fixture.selection.loadMoreRecentConversations();
    expect(fixture.selection.recentLoadFailed.value, isTrue);
    expect(fixture.selection.visibleConversations, rows.take(20).toList());
    fail = false;
    await fixture.selection.loadMoreRecentConversations();
    expect(fixture.selection.visibleConversations, rows);
    expect(fixture.selection.recentHasMore.value, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('duplicate load and obsolete search response are ignored',
      (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    final rows = List.generate(21,
        (i) => recentConversation(id: '$i', name: 'chat $i', group: i == 20));
    final fixture = RecentConversationFixture(
        data: rows,
        isJoinedGroup: (_) {
          calls++;
          return pending.future;
        });
    await fixture.open(tester);
    await fixture.selection.reloadRecentConversations();
    final loading = fixture.selection.loadMoreRecentConversations();
    await fixture.selection.loadMoreRecentConversations();
    expect(calls, 1);
    fixture.selection.searchConversations('chat 0');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    pending.complete(true);
    await loading;
    expect(fixture.selection.visibleConversations, [rows.first]);
    expect(fixture.selection.recentLoading.value, isFalse);
  });
}
