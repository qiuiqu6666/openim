import 'dart:async';

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_directory.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';
import 'package:openim/pages/contacts/presence_label.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim_common/openim_common.dart';

import 'support/chat_history_sender_presence_fixture.dart';

Finder _label(String id, Finder matching) =>
    find.descendant(of: senderPresenceRow(id), matching: matching);
Finder _letter(String label) =>
    find.descendant(of: find.byType(IndexBar), matching: find.text(label));

Future<void> _query(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 310));
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} sender presence respects privacy and display',
        (tester) async {
      final fixture = SenderPresenceFixture();
      await fixture.open(tester, brightness: brightness);
      expect(_label('1001', find.text('丁一')), findsOneWidget);
      expect(find.text('会话显示别名'), findsNothing);
      expect(_label('1001', find.text('presenceOnline'.tr)), findsOneWidget);
      expect(_label('1002', find.textContaining('小时前在线')), findsOneWidget);
      expect(_label('2001', find.text('presenceRecently'.tr)), findsOneWidget);
      expect(_label('2001', find.text('presenceOnline'.tr)), findsNothing);
      expect(_label('4001', find.byType(PresenceLabel)), findsNothing);
      expect(_label('4001', find.text('presenceOffline'.tr)), findsNothing,
          reason: 'A missing presence record must not imply offline status.');
      final before = tester.getSize(senderPresenceRow('1001')).height;
      final owner = fixture.contacts.owners.keys.single;
      expect(fixture.contacts.owners[owner], containsAll(['1001', '1002']));

      FriendDisplayPreferences.setOnlineStatus(false);
      await tester.pumpAndSettle();
      expect(find.text('presenceOnline'.tr), findsNothing);
      expect(find.textContaining('小时前在线'), findsNothing);
      expect(find.text('presenceRecently'.tr), findsNothing);
      expect(
          tester.getSize(senderPresenceRow('1001')).height, closeTo(before, 1));
      expect(fixture.contacts.owners[owner], isEmpty);
      expect(fixture.contacts.presence.users['2001']!.online, isTrue);

      FriendDisplayPreferences.setOnlineStatus(true);
      fixture.contacts.presence.users['1001'] = UserPresence(
          false,
          DateTime.now()
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch);
      await tester.pumpAndSettle();
      expect(_label('1001', find.textContaining('分钟前在线')), findsOneWidget);
      expect(_label('2001', find.text('presenceOnline'.tr)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} sender nickname and presence fit large text',
        (tester) async {
      final member =
          const ChatHistorySender(userID: '1001', displayName: senderLongName);
      final fixture = SenderPresenceFixture(
          source: SenderPresenceSource(members: [member]));
      await fixture.open(tester,
          brightness: brightness, width: 320, textScale: 2);
      final row = senderPresenceRow('1001');
      expect(row.hitTestable(), findsOneWidget);
      expect(_label('1001', find.text(senderLongName)), findsOneWidget);
      expect(_label('1001', find.text('presenceOnline'.tr)), findsOneWidget);
      expect(tester.getRect(row).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(row).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(fixture.selected, same(member));
      expect(fixture.contacts.owners, isEmpty);
    });
  }

  testWidgets(
      'sender presence owner pauses, filters and releases independently',
      (tester) async {
    final fixture = SenderPresenceFixture();
    final mainOwner = Object();
    fixture.contacts
        .setDirectoryPresenceVisible(mainOwner, {'1001', 'directory-friend'});
    await fixture.open(tester);
    final owner =
        fixture.contacts.owners.keys.singleWhere((value) => value != mainOwner);
    await _query(tester, 'David');
    expect(fixture.contacts.owners[owner], {'1002'});
    expect(fixture.contacts.owners[mainOwner], {'1001', 'directory-friend'});

    unawaited(showDialog<void>(
        context: fixture.boundary.currentContext!,
        builder: (_) => const AlertDialog(title: Text('测试覆盖页面'))));
    await tester.pumpAndSettle();
    expect(fixture.contacts.owners[owner], isEmpty);
    expect(fixture.contacts.owners[mainOwner], {'1001', 'directory-friend'});
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fixture.contacts.owners[owner], {'1002'});

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(fixture.contacts.owners[owner], isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.contacts.owners[owner], {'1002'});

    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fixture.contacts.owners.containsKey(owner), isFalse);
    expect(fixture.contacts.owners[mainOwner], {'1001', 'directory-friend'});
    expect(
        fixture.contacts.batches.lastWhere((batch) => batch.owner == owner).ids,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change clears sender rows and old presence ownership',
      (tester) async {
    final fixture = SenderPresenceFixture();
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys.single;
    fixture.source.currentUserID = 'another-account';
    fixture.contacts.currentSession = false;
    await tester.tap(senderPresenceRow('1001'));
    await tester.pumpAndSettle();
    expect(fixture.selected, isNull);
    expect(senderPresenceRow('1001'), findsNothing);
    expect(find.byType(PresenceLabel), findsNothing);
    expect(fixture.contacts.owners[owner] ?? {}, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    fixture.contacts.presence.users['1001'] = UserPresence(true, null);
    await tester.pumpAndSettle();
    expect(find.byType(PresenceLabel), findsNothing);
    expect(fixture.contacts.owners[owner] ?? {}, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'official sender metadata stays online with no cache within the owner fence',
      (tester) async {
    const member = ChatHistorySender(
      userID: 'official-service',
      displayName: '官方服务',
      ex: '{"accountType":"official"}',
    );
    final fixture =
        SenderPresenceFixture(source: SenderPresenceSource(members: [member]));
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys.single;
    expect(fixture.contacts.presence.users[member.userID], isNull);
    expect(
        _label(member.userID, find.text('presenceOnline'.tr)), findsOneWidget);

    final offline = UserPresence(false, null, showLastSeen: false);
    fixture.contacts.presence.users[member.userID] = offline;
    await tester.pumpAndSettle();
    expect(
        _label(member.userID, find.text('presenceOnline'.tr)), findsOneWidget);
    expect(fixture.contacts.presence.users[member.userID], same(offline));

    FriendDisplayPreferences.setOnlineStatus(false);
    await tester.pumpAndSettle();
    expect(_label(member.userID, find.byType(PresenceLabel)), findsNothing);
    expect(fixture.contacts.owners[owner], isEmpty);
    FriendDisplayPreferences.setOnlineStatus(true);
    await tester.pumpAndSettle();
    expect(
        _label(member.userID, find.text('presenceOnline'.tr)), findsOneWidget);

    fixture.source.currentUserID = 'another-account';
    fixture.contacts.currentSession = false;
    fixture.contacts.presence.users[member.userID] = UserPresence(true, null);
    await tester.pumpAndSettle();
    expect(senderPresenceRow(member.userID), findsOneWidget);
    expect(_label(member.userID, find.byType(PresenceLabel)), findsNothing,
        reason: 'Official presence must still respect the current owner.');
    await tester.tap(senderPresenceRow(member.userID));
    await tester.pumpAndSettle();
    expect(fixture.selected, isNull);
    expect(senderPresenceRow(member.userID), findsNothing);
    expect(fixture.contacts.owners[owner] ?? {}, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'letter gestures update visible presence and return the same sender',
      (tester) async {
    final source = SenderPresenceSource(members: [
      for (var i = 0; i < 20; i++)
        ChatHistorySender(userID: 'd$i', displayName: '丁$i'),
      for (var i = 0; i < 20; i++)
        ChatHistorySender(userID: 'q$i', displayName: '钱$i'),
      const ChatHistorySender(userID: 'other', displayName: '🍀'),
    ]);
    final fixture = SenderPresenceFixture(source: source);
    for (final member in source.members) {
      fixture.contacts.presence.users[member.userID] = UserPresence(true, null);
    }
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys.single;
    final rows = tester
        .widget<AzListView>(find.byType(AzListView))
        .data
        .cast<ChatHistorySenderRow>();
    final firstD =
        rows.firstWhere((row) => row.getSuspensionTag() == 'D').sender.userID;
    final firstQ =
        rows.firstWhere((row) => row.getSuspensionTag() == 'Q').sender.userID;
    await tester.tap(_letter('Q'));
    await tester.pumpAndSettle();
    expect(senderPresenceRow(firstQ).hitTestable(), findsOneWidget);
    expect(fixture.contacts.owners[owner], contains(firstQ));
    expect(fixture.contacts.owners[owner], isNot(contains(firstD)));

    final gesture = await tester.startGesture(tester.getCenter(_letter('Q')));
    await gesture.moveTo(tester.getCenter(_letter('D')));
    await gesture.moveBy(const Offset(0, -1));
    await tester.pumpAndSettle();
    expect(senderPresenceRow(firstD).hitTestable(), findsOneWidget);
    await gesture.moveTo(tester.getCenter(_letter('#')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.contacts.owners[owner], contains('other'));
    await tester.tap(senderPresenceRow('other'));
    await tester.pumpAndSettle();
    expect(fixture.selected, same(source.members.last));
    expect(fixture.contacts.owners.containsKey(owner), isFalse);
    expect(tester.takeException(), isNull);
  });
}
