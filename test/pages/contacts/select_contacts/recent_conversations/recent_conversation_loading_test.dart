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
  await tester.tap(find.byKey(const ValueKey('forward-send')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
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

  testWidgets(
      'departed selected group aborts the entire send and removes selection',
      (tester) async {
    var joined = true;
    final fixture =
        RecentConversationFixture(isJoinedGroup: (_) async => joined);
    await fixture.open(tester);
    await fixture.selection.reloadRecentConversations();
    await tester.pumpAndSettle();
    await tester.tap(recentConversationRow('single'));
    await tester.tap(recentConversationRow('group'));
    await tester.pumpAndSettle();
    var returned = false;
    fixture.result.then((_) => returned = true);
    joined = false;
    await _accept(tester);
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(find.byType(SelectContactsPage), findsOneWidget);
    expect(fixture.selection.checkedList.keys, ['user-single']);
    expect(recentConversationRow('group'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending send check blocks duplicate confirmation and reload',
      (tester) async {
    final reply = Completer<bool>();
    var calls = 0;
    final fixture = RecentConversationFixture(isJoinedGroup: (_) {
      calls++;
      return reply.future;
    });
    await fixture.open(tester);
    await tester.tap(recentConversationRow('group'));
    await tester.pumpAndSettle();
    var returned = false;
    fixture.result.then((_) => returned = true);
    await _accept(tester);
    expect(calls, 1);
    expect(returned, isFalse);
    expect(fixture.selection.enabledConfirmButton, isFalse);
    await fixture.selection.confirmSelectedList();
    await fixture.selection.reloadRecentConversations();
    expect(calls, 1);
    reply.complete(true);
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account changes during send check never return recipients',
      (tester) async {
    final reply = Completer<bool>();
    final fixture =
        RecentConversationFixture(isJoinedGroup: (_) => reply.future);
    await fixture.open(tester);
    await tester.tap(recentConversationRow('group'));
    await tester.pumpAndSettle();
    var returned = false;
    fixture.result.then((_) => returned = true);
    await _accept(tester);
    OpenIM.iMManager.userID = 'other';
    reply.complete(true);
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(find.byType(SelectContactsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'SDK failure retains selection for retry without returning recipients',
      (tester) async {
    final fixture = RecentConversationFixture(
        isJoinedGroup: (_) async => throw StateError('offline'));
    await fixture.open(tester);
    await tester.tap(recentConversationRow('group'));
    await tester.pumpAndSettle();
    var returned = false;
    fixture.result.then((_) => returned = true);
    await _accept(tester);
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(fixture.selection.checkedList.keys, ['group-group']);
    expect(fixture.selection.enabledConfirmButton, isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
