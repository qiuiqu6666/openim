import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_view.dart';
import 'package:openim_common/openim_common.dart';

import 'support/recent_conversation_fixture.dart';

Finder get _confirm => find.descendant(
    of: find.byType(CheckedConfirmView), matching: find.byType(Button));

Future<void> _accept(WidgetTester tester) async {
  await tester.tap(_confirm);
  await tester.pumpAndSettle();
  final card = find.byType(ContactCardSendDialog);
  await tester.tap(card.evaluate().isNotEmpty
      ? find.descendant(of: card, matching: find.byType(FilledButton))
      : find.byKey(const ValueKey('forward-send')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('selected group submits while other chats load ($brightness)',
        (tester) async {
      final pending = Completer<bool>();
      var background = false;
      var sending = false;
      final sendChecks = <String>[];
      final fixture = RecentConversationFixture(isJoinedGroup: (id) {
        if (sending) {
          sendChecks.add(id);
          return Future.value(true);
        }
        return background ? pending.future : Future.value(true);
      });
      await fixture.open(tester, brightness: brightness);
      await fixture.selection.reloadRecentConversations();
      background = true;
      final loading = fixture.selection.reloadRecentConversations();
      await tester.pump();
      await tester.tap(recentConversationRow('group'));
      await tester.pump();
      expect(fixture.selection.recentLoading.value, isTrue);
      expect(tester.widget<Button>(_confirm).enabled, isTrue);
      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('forward-send')), findsOneWidget);
      // A late background response must not remove the dialog's recipient.
      pending.complete(false);
      await loading;
      expect(fixture.selection.checkedList.keys, ['group-group']);
      sending = true;
      await tester.tap(find.byKey(const ValueKey('forward-send')));
      await tester.pumpAndSettle();
      final result = await fixture.result as Map;
      expect((result['checkedList'] as List).single.groupID, 'group-group');
      expect(sendChecks, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('single chat submits before pending group checks finish',
      (tester) async {
    final pending = Completer<bool>();
    final fixture =
        RecentConversationFixture(isJoinedGroup: (_) => pending.future);
    await fixture.open(tester);
    final loading = fixture.selection.reloadRecentConversations();
    await tester.pump();
    await tester.tap(recentConversationRow('single'));
    await tester.pump();
    await _accept(tester);
    await tester.pumpAndSettle();
    final result = await fixture.result as Map;
    expect((result['checkedList'] as List).single.userID, 'user-single');
    expect(pending.isCompleted, isFalse);
    pending.complete(true);
    await loading;
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel confirmation resumes interrupted directory loading',
      (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    final fixture = RecentConversationFixture(isJoinedGroup: (_) {
      calls++;
      return calls <= 2 ? pending.future : Future.value(true);
    });
    await fixture.open(tester);
    final loading = fixture.selection.reloadRecentConversations();
    await tester.pump();
    await tester.tap(recentConversationRow('single'));
    await tester.pump();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    fixture.navigator.currentState!.pop(false);
    await tester.pumpAndSettle();
    expect(calls, 4);
    expect(fixture.selection.checkedList.keys, ['user-single']);
    expect(recentConversationRow('group'), findsOneWidget);
    pending.complete(true);
    await loading;
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening displays confirmed groups while SDK is blocked',
      (tester) async {
    final fixture = RecentConversationFixture();
    await fixture.open(tester);
    await fixture.selection.reloadRecentConversations();
    final reply = Completer<bool>();
    final reopened = SelectContactsLogic(isJoinedGroup: (_) => reply.future)
      ..action = SelAction.forward;
    final loading = reopened.reloadRecentConversations();
    expect(reopened.recentLoading.value, isTrue);
    expect(reopened.conversationList.map((row) => row.conversationID),
        fixture.data.map((row) => row.conversationID));
    reply.complete(true);
    await loading;
    reopened.onClose();
  });

  for (final action in [SelAction.forward, SelAction.recommend]) {
    for (final outcome in ['pending', 'failure', 'not joined']) {
      testWidgets('$action searched group submits without $outcome SDK lookup',
          (tester) async {
        final pending = Completer<bool>();
        var calls = 0;
        final fixture = RecentConversationFixture(isJoinedGroup: (_) {
          calls++;
          if (outcome == 'failure') return Future.error(StateError('offline'));
          if (outcome == 'not joined') return Future.value(false);
          return pending.future;
        });
        await fixture.open(tester);
        fixture.selection.action = action;
        if (action == SelAction.recommend) {
          fixture.selection.sharedContact =
              UserInfo(userID: 'recommended-peer', nickname: '推荐好友');
        }
        fixture.selection.searchConversations('项目');
        await tester.pumpAndSettle();
        await tester.tap(recentConversationRow('group'));
        await tester.pump();
        await _accept(tester);
        await tester.pumpAndSettle();
        final result = await fixture.result as Map;
        expect((result['checkedList'] as List).single.groupID, 'group-group');
        expect(calls, 0);
        expect(pending.isCompleted, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('open confirmation blocks duplicate confirmation and reload',
      (tester) async {
    var calls = 0;
    final fixture = RecentConversationFixture(isJoinedGroup: (_) async {
      calls++;
      return true;
    });
    await fixture.open(tester);
    await tester.tap(recentConversationRow('group'));
    await tester.pump();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(fixture.selection.enabledConfirmButton, isFalse);
    await fixture.selection.confirmSelectedList();
    await fixture.selection.reloadRecentConversations();
    expect(calls, 0);
    expect(find.byKey(const ValueKey('forward-send')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('forward-send')));
    await tester.pumpAndSettle();
    final result = await fixture.result as Map;
    expect((result['checkedList'] as List).length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account changes during confirmation never return recipients',
      (tester) async {
    final fixture = RecentConversationFixture();
    await fixture.open(tester);
    await tester.tap(recentConversationRow('group'));
    await tester.pump();
    var returned = false;
    fixture.result.then((_) => returned = true);
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    OpenIM.iMManager.userID = 'other';
    await tester.tap(find.byKey(const ValueKey('forward-send')));
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(find.byType(SelectContactsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
