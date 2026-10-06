import 'dart:async';

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/presence_label.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim_common/openim_common.dart';

import 'support/friend_picker_presence_fixture.dart';

Future<void> _query(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search replaces the picker presence IDs without touching others',
      (tester) async {
    final fixture = FriendPickerPresenceFixture();
    final directoryOwner = Object();
    fixture.contacts.setDirectoryPresenceVisible(
        directoryOwner, {'1001', 'directory-friend'});
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys
        .singleWhere((value) => value != directoryOwner);
    expect(fixture.contacts.owners[owner], {'1001', '1002', '2001', '4001'});

    await _query(tester, 'Bob');
    expect(friendPickerRow('2001').hitTestable(), findsOneWidget);
    expect(friendPickerRow('1001'), findsNothing);
    expect(fixture.contacts.owners[owner], {'2001'});
    expect(
        fixture.contacts.owners[directoryOwner], {'1001', 'directory-friend'});

    await _query(tester, 'missing-friend');
    expect(fixture.contacts.owners[owner], isEmpty);
    await _query(tester, '');
    expect(fixture.contacts.owners[owner], {'1001', '1002', '2001', '4001'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dialog coverage pauses presence and dismissal restores the filter',
      (tester) async {
    final fixture = FriendPickerPresenceFixture();
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys.single;
    await _query(tester, 'Bob');
    expect(fixture.contacts.owners[owner], {'2001'});

    unawaited(showDialog<void>(
      context: fixture.boundary.currentContext!,
      builder: (_) => const AlertDialog(title: Text('测试覆盖页面')),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.contacts.owners[owner], isEmpty);

    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.friends.searchQuery.value, 'bob');
    expect(fixture.contacts.owners[owner], {'2001'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('background transitions pause presence until the app resumes',
      (tester) async {
    final fixture = FriendPickerPresenceFixture();
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys.single;
    await _query(tester, 'Bob');

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      expect(fixture.contacts.owners[owner], isEmpty);
    }
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      expect(fixture.contacts.owners[owner], isEmpty);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.contacts.owners[owner], {'2001'});
    expect(fixture.friends.searchQuery.value, 'bob');
    expect(tester.takeException(), isNull);
  });

  for (final action in [SelAction.addMember, SelAction.forward]) {
    testWidgets(
        '${action.name} preference hides presence and releases visible IDs',
        (tester) async {
      final fixture = FriendPickerPresenceFixture(action: action);
      await fixture.open(tester);
      final owner = fixture.contacts.owners.keys.single;
      final visible = Set<String>.of(fixture.contacts.owners[owner]!);
      expect(visible, contains('1001'));
      expect(find.byType(PresenceLabel), findsWidgets);

      FriendDisplayPreferences.setOnlineStatus(false);
      await tester.pumpAndSettle();
      expect(find.byType(PresenceLabel), findsNothing);
      expect(fixture.contacts.owners[owner], isEmpty);
      expect(fixture.contacts.presence.users['1001']!.online, isTrue);

      FriendDisplayPreferences.setOnlineStatus(true);
      await tester.pumpAndSettle();
      expect(find.byType(PresenceLabel), findsWidgets);
      expect(fixture.contacts.owners[owner], visible);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('leaving the picker removes only its own presence owner',
      (tester) async {
    final fixture = FriendPickerPresenceFixture();
    final directoryOwner = Object();
    fixture.contacts.setDirectoryPresenceVisible(
        directoryOwner, {'1001', 'directory-friend'});
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys
        .singleWhere((value) => value != directoryOwner);

    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('父聊天页面'), findsOneWidget);
    expect(fixture.contacts.owners.containsKey(owner), isFalse);
    expect(
        fixture.contacts.owners[directoryOwner], {'1001', 'directory-friend'});
    expect(
        fixture.contacts.batches.lastWhere((batch) => batch.owner == owner).ids,
        isNull);

    final reports = fixture.contacts.batches.length;
    FriendDisplayPreferences.setOnlineStatus(false);
    fixture.contacts.presence.users['1001'] = UserPresence(false, null);
    await tester.pumpAndSettle();
    expect(fixture.contacts.batches, hasLength(reports));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale session cannot expose cached presence or keep ownership',
      (tester) async {
    final fixture = FriendPickerPresenceFixture();
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys.single;
    expect(find.byType(PresenceLabel), findsWidgets);

    fixture.contacts.currentSession = false;
    // A settings notification rebuilds the page while online display stays on.
    FriendDisplayPreferences.setReadReceipts(false);
    await tester.pumpAndSettle();
    expect(FriendDisplayPreferences.showOnlineStatus, isTrue);
    expect(fixture.contacts.presence.users['1001']!.online, isTrue);
    expect(find.byType(PresenceLabel), findsNothing);
    expect(fixture.contacts.owners[owner], isEmpty);

    fixture.contacts.presence.users['1001'] = UserPresence(
        false,
        DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch);
    await tester.pumpAndSettle();
    expect(find.byType(PresenceLabel), findsNothing);
    expect(fixture.contacts.owners[owner], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'scrolling replaces visible subscriptions and excludes distant rows',
      (tester) async {
    final data = [
      for (var i = 0; i < 40; i++)
        ISUserInfo.fromJson({
          'userID': 'friend-$i',
          'nickname': 'Alice ${i.toString().padLeft(2, '0')}',
          'tagIndex': 'A',
          'namePinyin': 'ALICE ${i.toString().padLeft(2, '0')}',
        }),
    ];
    SuspensionUtil.setShowSuspensionStatus(data);
    final fixture = FriendPickerPresenceFixture(data: data);
    await fixture.open(tester);
    final owner = fixture.contacts.owners.keys.single;
    final firstVisible = Set<String>.of(fixture.contacts.owners[owner]!);
    expect(firstVisible, contains('friend-0'));
    expect(firstVisible.length, lessThan(data.length));
    expect(firstVisible, isNot(contains('friend-39')));

    await tester.drag(find.byType(AzListView), const Offset(0, -850));
    await tester.pumpAndSettle();
    final afterScroll = fixture.contacts.owners[owner]!;
    expect(afterScroll, isNotEmpty);
    expect(afterScroll, isNot(contains('friend-0')));
    expect(afterScroll, isNot(contains('friend-39')));
    expect(afterScroll.difference(firstVisible), isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
