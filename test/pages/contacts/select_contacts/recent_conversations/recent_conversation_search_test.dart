import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_view.dart';
import 'package:openim_common/openim_common.dart';

import 'support/recent_conversation_fixture.dart';

Finder get _search => find.descendant(
    of: find.byKey(const ValueKey('select-conversations-search')),
    matching: find.byType(TextField));

Future<void> _query(WidgetTester tester, String text) async {
  await tester.enterText(_search, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _clear(WidgetTester tester) async {
  final icon = find.byWidgetPredicate((widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == ImageRes.clearText);
  await tester.tap(icon);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loading and searching only check up to 20 matching groups',
      (tester) async {
    final calls = <String>[];
    final rows = [
      for (var i = 0; i < 100; i++)
        recentConversation(id: '$i', name: 'Group $i', group: true),
    ];
    final fixture = RecentConversationFixture(
        data: rows,
        isJoinedGroup: (id) async {
          calls.add(id);
          return true;
        });
    await fixture.open(tester);
    await fixture.selection.reloadRecentConversations();
    await tester.pumpAndSettle();
    expect(calls, rows.take(20).map((row) => row.groupID).toList());
    expect(fixture.selection.conversationList, hasLength(20));
    calls.clear();
    await _query(tester, 'Group 99');
    expect(calls, ['group-99']);
    expect(fixture.selection.conversationList, [rows.last]);
    calls.clear();
    await _clear(tester);
    expect(calls, rows.take(20).map((row) => row.groupID).toList());
    expect(fixture.selection.conversationList, hasLength(20));
  });
  testWidgets('recent list starts with 20 and search can find older chats',
      (tester) async {
    final rows = [
      for (var i = 0; i < 65; i++) recentConversation(id: '$i', name: '联系人$i'),
    ];
    final fixture = RecentConversationFixture(data: rows);
    await fixture.open(tester);
    expect(fixture.selection.visibleConversations, rows.take(20).toList());
    await _query(tester, '联系人64');
    expect(fixture.selection.visibleConversations, [rows.last]);
    await _query(tester, '联系人');
    expect(fixture.selection.visibleConversations, hasLength(20));
    await _clear(tester);
    expect(fixture.selection.visibleConversations, rows.take(20).toList());
  });
  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} search filters names and clears empty state',
        (tester) async {
      final friend = recentConversation(id: 'friend', name: 'Alice 小林');
      final group =
          recentConversation(id: 'group', name: 'ALICE 协作群', group: true);
      final unrelated = recentConversation(
          id: 'other', name: '小张', message: recentMessage(text: 'Alice 的消息'));
      final fixture =
          RecentConversationFixture(data: [friend, group, unrelated]);
      await fixture.open(tester,
          brightness: brightness, width: 320, textScale: 2);

      await _query(tester, '  aLiCe  ');
      expect(recentConversationRow('friend'), findsOneWidget);
      expect(recentConversationRow('group'), findsOneWidget);
      expect(recentConversationRow('other'), findsNothing);
      expect(fixture.selection.visibleConversations, [friend, group]);
      expect(find.text(StrRes.myFriend), findsOneWidget);
      expect(find.text(StrRes.myGroup), findsOneWidget);

      await _query(tester, '不存在的名称');
      expect(find.text(StrRes.searchNotFound), findsOneWidget);
      expect(recentConversationRow('friend'), findsNothing);
      await _clear(tester);
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(find.text(StrRes.searchNotFound), findsNothing);
      expect(
          fixture.selection.visibleConversations, [friend, group, unrelated]);
      expect(recentConversationRow('friend'), findsOneWidget);
      expect(recentConversationRow('other'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recipients selected in different searches confirm together',
      (tester) async {
    final friend = recentConversation(id: 'friend', name: '小林');
    final group = recentConversation(id: 'group', name: '协作群', group: true);
    final fixture = RecentConversationFixture(data: [friend, group]);
    await fixture.open(tester);
    await _query(tester, '小林');
    await tester.tap(recentConversationRow('friend'));
    await _query(tester, '协作');
    expect(recentConversationRow('friend'), findsNothing);
    await tester.tap(recentConversationRow('group'));
    await _clear(tester);
    for (final id in ['friend', 'group']) {
      final radio = tester.widget<ChatRadio>(find.descendant(
          of: recentConversationRow(id), matching: find.byType(ChatRadio)));
      expect(radio.checked, isTrue);
    }
    await _query(tester, '没有结果');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse);
    await tester.tap(find.descendant(
        of: find.byType(CheckedConfirmView), matching: find.byType(Button)));
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<ForwardHintDialog>(find.byType(ForwardHintDialog));
    expect(dialog.checkedList, [same(friend), same(group)]);
    await tester.tap(find.descendant(
        of: find.byType(ForwardHintDialog),
        matching: find.byKey(const ValueKey('forward-send'))));
    await tester.pumpAndSettle();
    final result = await fixture.result;
    expect((result['checkedList'] as Iterable).toList(),
        [same(friend), same(group)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search returns to the top after scrolling and tracks list changes',
      (tester) async {
    final fixture = RecentConversationFixture(data: [
      for (var i = 0; i < 100; i++)
        recentConversation(id: '$i', name: i == 0 ? '目标群' : '联系人$i'),
    ]);
    await fixture.open(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(fixture.selection.recentScrollController.offset, greaterThan(0));
    await _query(tester, '目标');
    expect(fixture.selection.recentScrollController.offset, 0);
    expect(recentConversationRow('0').hitTestable(), findsOneWidget);
    expect(fixture.selection.visibleConversations, hasLength(1));
    final added = recentConversation(id: 'new', name: '目标好友');
    fixture.selection.conversationList.add(added);
    await tester.pumpAndSettle();
    expect(recentConversationRow('new'), findsOneWidget);
    expect(fixture.selection.visibleConversations, hasLength(2));
    expect(fixture.selection.conversationList, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
