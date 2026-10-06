import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/presence_label.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/official_account/official_account_chrome_tokens.dart';
import 'package:openim_common/openim_common.dart';

import 'support/friend_picker_presence_fixture.dart';

Finder _within(String id, Finder target) =>
    find.descendant(of: friendPickerRow(id), matching: target);

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void _expectAlphabetFits(WidgetTester tester) {
  final list = tester.widget<AzListView>(find.byType(AzListView));
  final index = tester.widget<IndexBar>(find.byType(IndexBar));
  for (final tag in ['A', 'B', 'Z']) {
    final labels =
        find.descendant(of: find.byType(AzListView), matching: find.text(tag));
    expect(labels, findsWidgets);
    for (final element in labels.evaluate()) {
      final label =
          find.byElementPredicate((value) => identical(value, element));
      // Initial-based avatars are not alphabet navigation labels.
      if (find
          .ancestor(of: label, matching: find.byType(AvatarView))
          .evaluate()
          .isNotEmpty) {
        continue;
      }
      final render = element.findRenderObject()! as RenderParagraph;
      final requiredHeight = render.getMaxIntrinsicHeight(render.size.width);
      final inIndex = find
          .ancestor(of: label, matching: find.byType(IndexBar))
          .evaluate()
          .isNotEmpty;
      expect(inIndex ? index.itemHeight : list.susItemHeight,
          greaterThanOrEqualTo(requiredHeight - .01),
          reason:
              '$tag must fit its scaled line height without silent clipping.');
      expect(render.size.height, greaterThanOrEqualTo(requiredHeight - .01));
    }
  }
}

void _expectFirstRowBelowHeader(WidgetTester tester, String id) {
  final list = tester.widget<AzListView>(find.byType(AzListView));
  final listTop = tester.getTopLeft(find.byType(AzListView)).dy;
  expect(tester.getTopLeft(friendPickerRow(id)).dy,
      greaterThanOrEqualTo(listTop + list.susItemHeight - .01),
      reason: 'The floating group header must not cover the first friend.');
}

void main() {
  List<ISUserInfo> officialSamples() => [
        ISUserInfo.fromJson(
            {'userID': '99Pay', 'nickname': '99Pay', 'tagIndex': 'A'}),
        ISUserInfo.fromJson({
          'userID': 'notice',
          'nickname': '公告',
          'tagIndex': 'A',
          'ex': '{"accountType":"official","officialRole":"message"}'
        }),
        ISUserInfo.fromJson(
            {'userID': 'ordinary', 'nickname': '99Message', 'tagIndex': 'A'}),
        ISUserInfo.fromJson({
          'userID': 'assistant',
          'nickname': '官方助手',
          'tagIndex': 'A',
          'ex': '{"accountType":"official","officialRole":"assistant"}'
        }),
      ];
  Finder badge(String id) => _within(
      id,
      find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              OfficialAccountChromeTokens.badgeAsset));

  testWidgets(
      'assistant stays online in the picker while notification rows stay read only',
      (tester) async {
    final data = [
      for (final id in ['assistant', 'ordinary', '99Message', '99Pay'])
        ISUserInfo.fromJson({
          'userID': id,
          'nickname': id == 'ordinary' || id == 'assistant' ? 'AI助理' : id,
          'tagIndex': 'A',
        }),
    ];
    final fixture =
        FriendPickerPresenceFixture(action: SelAction.forward, data: data);
    fixture.contacts.presence.users.assignAll({
      for (final friend in data) friend.userID!: UserPresence(false, null),
    });
    await fixture.open(tester);
    expect(
        _within('assistant', find.text('presenceOnline'.tr)), findsOneWidget);
    expect(_within('ordinary', find.text('presenceOffline'.tr)), findsOneWidget,
        reason: 'The same nickname does not make a personal account official.');
    for (final id in ['99Message', '99Pay']) {
      expect(_within(id, find.text('仅接收通知')), findsOneWidget);
      expect(tester.widget<InkWell>(friendPickerRow(id)).onTap, isNull);
      await tester.tap(friendPickerRow(id), warnIfMissed: false);
    }
    expect(fixture.selection.checkedList, isEmpty);

    fixture.contacts.presence.users['assistant'] =
        UserPresence(false, 123456, showLastSeen: false);
    await tester.pumpAndSettle();
    expect(
        _within('assistant', find.text('presenceOnline'.tr)), findsOneWidget);
    expect(
        _within('ordinary', find.text('presenceOffline'.tr)), findsOneWidget);
    expect(fixture.contacts.presence.users['assistant']!.online, isFalse);
    expect(fixture.contacts.presence.users['assistant']!.showLastSeen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'forward friend list shows official accounts without selecting them',
      (tester) async {
    final fixture = FriendPickerPresenceFixture(
        action: SelAction.forward, data: officialSamples());
    await fixture.open(tester);
    for (final id in ['99Pay', 'notice']) {
      expect(friendPickerRow(id), findsOneWidget);
      expect(badge(id), findsOneWidget);
      expect(tester.widget<InkWell>(friendPickerRow(id)).onTap, isNull);
      expect(_within(id, find.text('仅接收通知')), findsOneWidget);
      await tester.tap(friendPickerRow(id), warnIfMissed: false);
    }
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList, isEmpty);
    expect(badge('ordinary'), findsNothing);
    expect(badge('assistant'), findsOneWidget);
    await tester.tap(find.text(StrRes.selectAll));
    await tester.pumpAndSettle();
    expect(
        fixture.selection.checkedList.keys.toSet(), {'ordinary', 'assistant'});
    expect(fixture.friends.isSelectAll, isTrue);
    await tester.tap(find.text(StrRes.selectAll));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'contact card recipient flow continues to hide notification accounts',
      (tester) async {
    final fixture = FriendPickerPresenceFixture(
        action: SelAction.recommend, data: officialSamples());
    await fixture.open(tester);
    expect(friendPickerRow('99Pay'), findsNothing);
    expect(friendPickerRow('notice'), findsNothing);
    expect(friendPickerRow('ordinary'), findsOneWidget);
    expect(badge('ordinary'), findsNothing);
    expect(badge('assistant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} friend names and real presence respect privacy',
        (tester) async {
      final fixture = FriendPickerPresenceFixture();
      await fixture.open(tester, brightness: brightness);
      expect(_within('1001', find.text('Alice')), findsOneWidget,
          reason: 'The picker keeps the existing showName remark preference.');
      expect(_within('1001', find.text('presenceOnline'.tr)), findsOneWidget);
      expect(_within('1002', find.textContaining('小时前在线')), findsOneWidget);
      expect(_within('2001', find.text('presenceRecently'.tr)), findsOneWidget);
      expect(_within('2001', find.text('presenceOnline'.tr)), findsNothing);
      expect(_within('4001', find.byType(PresenceLabel)), findsNothing);
      expect(_within('4001', find.text('presenceOffline'.tr)), findsNothing);
      final before = tester.getSize(friendPickerRow('1001')).height;
      FriendDisplayPreferences.setOnlineStatus(false);
      await tester.pumpAndSettle();
      expect(find.byType(PresenceLabel), findsNothing);
      expect(
          tester.getSize(friendPickerRow('1001')).height, closeTo(before, 1));
      FriendDisplayPreferences.setOnlineStatus(true);
      fixture.contacts.presence.users['1001'] = UserPresence(
          false,
          DateTime.now()
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch);
      await tester.pumpAndSettle();
      expect(_within('1001', find.textContaining('分钟前在线')), findsOneWidget);
      expect(_within('2001', find.text('presenceOnline'.tr)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final action in [SelAction.forward, SelAction.addMember]) {
      testWidgets('${brightness.name} ${action.name} fits 320px at 200% text',
          (tester) async {
        final data = friendPickerSamples();
        data[0] = ISUserInfo.fromJson({
          ...data[0].toJson(),
          'remark': friendPickerLongName,
        });
        final fixture = FriendPickerPresenceFixture(action: action, data: data);
        await fixture.open(tester,
            brightness: brightness, width: 320, textScale: 2);
        final row = friendPickerRow('1001');
        expect(row.hitTestable(), findsOneWidget);
        expect(
            _within('1001', find.text(friendPickerLongName)), findsOneWidget);
        expect(_within('1001', find.text('presenceOnline'.tr)), findsOneWidget);
        expect(tester.getRect(row).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(row).right, lessThanOrEqualTo(320));
        _expectAlphabetFits(tester);
        _expectFirstRowBelowHeader(tester, '1001');
        expect(tester.takeException(), isNull);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(fixture.selection.checkedList.keys, ['1001']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final action in [SelAction.forward, SelAction.addMember]) {
    testWidgets('${action.name} keeps individual and select-all selection',
        (tester) async {
      final fixture = FriendPickerPresenceFixture(action: action);
      fixture.selection.defaultCheckedIDList.add('1002');
      await fixture.open(tester);
      await tester.tap(friendPickerRow('1001'));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys, ['1001']);
      expect(fixture.selection.checkedList['1001'], same(fixture.data.first));
      await tester.tap(friendPickerRow('1001'));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList, isEmpty);
      await tester.tap(friendPickerRow('1002'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList, isEmpty);
      await tester.tap(find.text(StrRes.selectAll));
      await tester.pumpAndSettle();
      expect(
          fixture.selection.checkedList.keys.toSet(), {'1001', '2001', '4001'});
      expect(fixture.friends.isSelectAll, isTrue);
      await tester.tap(find.text(StrRes.selectAll));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('filtering to a later friend keeps a group header above its name',
      (tester) async {
    final fixture = FriendPickerPresenceFixture();
    await fixture.open(tester, width: 320, textScale: 2);
    await _query(tester, 'Aster');
    expect(friendPickerRow('1001'), findsNothing);
    expect(friendPickerRow('1002'), findsOneWidget);
    _expectFirstRowBelowHeader(tester, '1002');
    await tester.tap(friendPickerRow('1002'));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys, ['1002']);
    await _query(tester, '');
    _expectFirstRowBelowHeader(tester, '1001');
    expect(fixture.selection.checkedList.keys, ['1002']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'filtered select-all preserves selected friends outside the filter',
      (tester) async {
    final fixture = FriendPickerPresenceFixture();
    await fixture.open(tester);
    await tester.tap(friendPickerRow('1001'));
    await tester.pumpAndSettle();
    await _query(tester, 'Bob');
    expect(friendPickerRow('1001'), findsNothing);
    expect(friendPickerRow('2001'), findsOneWidget);
    await tester.tap(find.text(StrRes.selectAll));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys.toSet(), {'1001', '2001'});
    await tester.tap(find.text(StrRes.selectAll));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys, ['1001']);
    await _query(tester, '');
    expect(friendPickerRow('1001'), findsOneWidget);
    expect(fixture.selection.checkedList.keys, ['1001']);
    expect(tester.takeException(), isNull);
  });
}
