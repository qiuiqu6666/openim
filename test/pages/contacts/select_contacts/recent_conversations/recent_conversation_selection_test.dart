import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_view.dart';
import 'package:openim/pages/official_account/official_account_chrome_tokens.dart';
import 'package:openim_common/openim_common.dart';

import 'support/recent_conversation_fixture.dart';

Finder get _confirm => find.descendant(
    of: find.byType(CheckedConfirmView), matching: find.byType(Button));

Finder _dialogAction(String text) => find.descendant(
    of: find.byType(ForwardHintDialog), matching: find.text(text));

ChatRadio _radio(WidgetTester tester, String id) =>
    tester.widget<ChatRadio>(find.descendant(
        of: recentConversationRow(id), matching: find.byType(ChatRadio)));

Future<void> _confirmAndReturn(
    WidgetTester tester, RecentConversationFixture fixture) async {
  final single = fixture.data[0];
  final group = fixture.data[1];
  await tester.tap(recentConversationRow(single.conversationID));
  await tester.tap(recentConversationRow(group.conversationID));
  await tester.pumpAndSettle();

  await tester.tap(_confirm);
  await tester.pumpAndSettle();
  final dialog =
      tester.widget<ForwardHintDialog>(find.byType(ForwardHintDialog));
  expect(dialog.title, fixture.selection.ex);
  expect(dialog.checkedList, hasLength(2));
  expect(dialog.checkedList[0], same(single));
  expect(dialog.checkedList[1], same(group));
  expect(tester.takeException(), isNull);
  expect(_dialogAction(StrRes.cancel).hitTestable(), findsOneWidget);
  await tester.tap(_dialogAction(StrRes.cancel));
  await tester.pumpAndSettle();
  expect(find.byType(ForwardHintDialog), findsNothing);
  expect(find.byType(SelectContactsPage), findsOneWidget);
  expect(fixture.selection.checkedList.keys.toSet(),
      {single.userID, group.groupID});

  await tester.tap(_confirm);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(_dialogAction(StrRes.determine).hitTestable(), findsOneWidget);
  await tester.tap(_dialogAction(StrRes.determine));
  await tester.pumpAndSettle();
  final result = await fixture.result;
  expect(result, isA<Map>());
  final recipients = (result['checkedList'] as Iterable).toList();
  expect(recipients, hasLength(2));
  expect(recipients[0], same(single));
  expect(recipients[1], same(group));
  expect(find.byType(ForwardHintDialog), findsNothing);
  expect(find.byType(SelectContactsPage), findsNothing);
  expect(find.text('父聊天页面'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  Finder badges(Finder parent) => find.descendant(
      of: parent,
      matching: find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              OfficialAccountChromeTokens.badgeAsset));

  testWidgets(
      'official recent destinations are recognizable but cannot be selected',
      (tester) async {
    final notice = recentConversation(id: 'notice', name: '99Message')
      ..userID = '99Message';
    final pay = recentConversation(id: 'pay', name: '支付通知')
      ..ex = '{"accountType":"official","officialRole":"pay"}';
    final ordinary = recentConversation(id: 'ordinary', name: '99Pay');
    final group =
        recentConversation(id: 'group', name: '99Message', group: true)
          ..groupID = '99Message'
          ..ex = '{"accountType":"official"}';
    final fixture =
        RecentConversationFixture(data: [notice, pay, ordinary, group]);
    await fixture.open(tester);
    for (final id in ['notice', 'pay']) {
      expect(recentConversationRow(id), findsOneWidget);
      expect(badges(recentConversationRow(id)), findsOneWidget);
      expect(tester.widget<InkWell>(recentConversationRow(id)).onTap, isNull);
      await tester.tap(recentConversationRow(id), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_radio(tester, id).checked, isFalse);
    }
    expect(fixture.selection.checkedList, isEmpty);
    expect(tester.widget<Button>(_confirm).enabled, isFalse);
    expect(badges(recentConversationRow('ordinary')), findsNothing);
    expect(badges(recentConversationRow('group')), findsNothing);
    await tester.tap(recentConversationRow('ordinary'));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys, ['user-ordinary']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forward confirmation retains verified SDK recipient identities',
      (tester) async {
    final assistant = recentConversation(id: 'assistant', name: '官方助手')
      ..ex = '{"accountType":"official","officialRole":"assistant"}';
    final ordinary = recentConversation(id: 'ordinary', name: '99Message');
    final fixture = RecentConversationFixture(data: [assistant, ordinary]);
    await fixture.open(tester);
    await tester.tap(recentConversationRow('assistant'));
    await tester.tap(recentConversationRow('ordinary'));
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    final dialog = find.byType(ForwardHintDialog);
    expect(badges(dialog), findsOneWidget);
    final widget = tester.widget<ForwardHintDialog>(dialog);
    expect(widget.checkedList.whereType<ConversationInfo>().first,
        same(assistant));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'individual and group selection retains recipient IDs and objects',
      (tester) async {
    final single = recentConversation(id: 'single', name: '小林');
    final group = recentConversation(id: 'group', name: '协作群', group: true);
    final fixture = RecentConversationFixture(data: [single, group]);
    final before = fixture.data.map((item) => item.toJson()).toList();
    await fixture.open(tester);
    expect(tester.widget<Button>(_confirm).enabled, isFalse);

    await tester.tap(recentConversationRow('single'));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys, ['user-single']);
    expect(fixture.selection.checkedList['user-single'], same(single));
    expect(_radio(tester, 'single').checked, isTrue);
    expect(tester.widget<Button>(_confirm).enabled, isTrue);

    await tester.tap(recentConversationRow('group'));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys.toSet(),
        {'user-single', 'group-group'});
    expect(fixture.selection.checkedList['group-group'], same(group));
    expect(_radio(tester, 'group').checked, isTrue);

    await tester.tap(recentConversationRow('single'));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys, ['group-group']);
    expect(_radio(tester, 'single').checked, isFalse);
    expect(_radio(tester, 'group').checked, isTrue);
    await tester.tap(recentConversationRow('group'));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList, isEmpty);
    expect(tester.widget<Button>(_confirm).enabled, isFalse);
    expect(fixture.data.map((item) => item.toJson()).toList(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default selected recipients cannot be toggled by row taps',
      (tester) async {
    final single = recentConversation(id: 'single');
    final group = recentConversation(id: 'group', group: true);
    final fixture = RecentConversationFixture(data: [single, group]);
    fixture.selection.defaultCheckedIDList
        .addAll(['user-single', 'group-group']);
    fixture.selection.checkedList.addAll({
      'user-single': single,
      'group-group': group,
    });
    await fixture.open(tester);

    for (final id in ['single', 'group']) {
      expect(_radio(tester, id).checked, isTrue);
      await tester.tap(recentConversationRow(id), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_radio(tester, id).checked, isTrue);
    }
    expect(fixture.selection.checkedList.keys.toSet(),
        {'user-single', 'group-group'});
    expect(fixture.selection.checkedList['user-single'], same(single));
    expect(fixture.selection.checkedList['group-group'], same(group));
    expect(find.byType(ForwardHintDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'confirmation can cancel then return the original selected objects',
      (tester) async {
    final single = recentConversation(id: 'single', name: '小林');
    final group = recentConversation(id: 'group', name: '协作群', group: true);
    final fixture = RecentConversationFixture(data: [single, group]);
    await fixture.open(tester);
    await _confirmAndReturn(tester, fixture);
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
    testWidgets(
        '${locale.toLanguageTag()} long recipients can confirm at 320px and 200% text',
        (tester) async {
      final single = recentConversation(
          id: 'single', name: '阿林特别长的好友备注与英文 Long personal recipient name');
      final group =
          recentConversation(id: 'group', name: recentLongName, group: true);
      final fixture = RecentConversationFixture(data: [single, group]);
      await fixture.open(tester, width: 320, textScale: 2, locale: locale);
      expect(tester.takeException(), isNull);
      await _confirmAndReturn(tester, fixture);
    });
  }

  testWidgets(
      'reactive conversation updates refresh the row and message preview',
      (tester) async {
    final original = recentConversation(
        id: 'single', name: '原来的昵称', message: recentMessage(text: '更新前的消息'));
    final fixture = RecentConversationFixture(data: [original]);
    await fixture.open(tester);
    expect(recentConversationPreview('single'), findsOneWidget);
    expect(find.text('更新前的消息'), findsOneWidget);
    await tester.tap(recentConversationRow('single'));
    await tester.pumpAndSettle();

    final updated = recentConversation(
        id: 'single',
        name: '更新后的昵称',
        message: recentMessage(id: 'new-message', text: '更新后的消息'));
    fixture.conversations.list[0] = updated;
    await tester.pumpAndSettle();
    expect(find.text('更新前的消息'), findsNothing);
    expect(find.text('更新后的消息'), findsOneWidget);
    expect(fixture.selection.conversationList.single, same(original));
    expect(_radio(tester, 'single').checked, isTrue);

    fixture.selection.conversationList[0] = updated;
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: recentConversationRow('single'), matching: find.text('更新后的昵称')),
        findsOneWidget);
    expect(_radio(tester, 'single').checked, isTrue);
    expect(fixture.selection.checkedList['user-single'], same(original));
    expect(original.showName, '原来的昵称');
    expect(original.latestMsg!.textElem!.content, '更新前的消息');

    fixture.selection.conversationList.clear();
    await tester.pumpAndSettle();
    expect(recentConversationRow('single'), findsNothing);
    expect(find.text(StrRes.recentConversations), findsNothing);
    expect(find.text(StrRes.myFriend), findsOneWidget);
    expect(find.text(StrRes.myGroup), findsOneWidget);
    expect(fixture.selection.checkedList['user-single'], same(original));
    expect(tester.widget<Button>(_confirm).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an empty recent list keeps category entry points and cannot confirm',
      (tester) async {
    final fixture = RecentConversationFixture(data: []);
    await fixture.open(tester);
    expect(find.text(StrRes.recentConversations), findsNothing);
    expect(find.text(StrRes.myFriend), findsOneWidget);
    expect(find.text(StrRes.myGroup), findsOneWidget);
    expect(tester.widget<Button>(_confirm).enabled, isFalse);
    await tester.tap(_confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(ForwardHintDialog), findsNothing);
    expect(find.byType(SelectContactsPage), findsOneWidget);
    expect(fixture.selection.checkedList, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
