import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_group_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local absence is pending until server verification completes',
      (tester) async {
    final server = Completer<bool>();
    final h = ChatGroupHarness(
      isJoined: (_) async => false,
      verifyMembership: (_, __) => server.future,
    );
    h.controller.initialize();
    h.controller.recover();
    await tester.pump();
    expect(h.controller.membershipPending.value, isTrue);
    expect(h.controller.isInvalidGroup, isFalse);
    expect(h.controller.sendingMuted, isTrue);
    expect(h.inputCleared, 0);
    server.complete(true);
    await tester.pump();
    expect(h.controller.isInGroup.value, isTrue);
    expect(h.controller.sendingMuted, isFalse);
    expect(h.profileReads, 1);
    h.controller.close();
  });

  testWidgets('negative local reads retry finitely then sync recovers',
      (tester) async {
    var local = false;
    final h = ChatGroupHarness(
      isJoined: (_) async => local,
      verifyMembership: (_, __) async => throw StateError('offline'),
    );
    h.controller.initialize();
    h.controller.recover();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 30));
    expect(h.joinedReads, 3);
    expect(h.controller.membershipPending.value, isTrue);
    expect(h.controller.isInvalidGroup, isFalse);
    expect(h.controller.sendingMuted, isTrue);
    local = true;
    unawaited(h.controller.refreshProfileAfterSync());
    await tester.pump();
    expect(h.controller.membershipPending.value, isFalse);
    expect(h.controller.sendingMuted, isFalse);
    h.controller.close();
  });

  testWidgets('server-confirmed departure resists stale local positives',
      (tester) async {
    var local = false;
    var server = false;
    final h = ChatGroupHarness(
      isJoined: (_) async => local,
      verifyMembership: (_, __) async => server,
    );
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    expect(h.controller.isInvalidGroup, isTrue);
    expect(h.inputCleared, 1);
    local = true;
    h.controller.recover(resetAttempts: true);
    await tester.pump();
    expect(h.controller.isInvalidGroup, isTrue);
    expect(h.joinedReads, 1);
    server = true;
    unawaited(h.controller.refreshProfileAfterSync());
    await tester.pump();
    expect(h.controller.isInvalidGroup, isFalse);
    expect(h.controller.isInGroup.value, isTrue);
    h.controller.close();
  });

  testWidgets('self added restores after leave without a joined-list event',
      (tester) async {
    final h = ChatGroupHarness();
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    h.deleted.add(GroupMembersInfo(groupID: 'group', userID: 'me'));
    expect(h.controller.isInvalidGroup, isTrue);
    expect(h.controller.groupMembersInfo, isNull);
    h.added.add(GroupMembersInfo(
        groupID: 'group', userID: 'me', roleLevel: GroupRoleLevel.member));
    await tester.pump();
    expect(h.controller.isInGroup.value, isTrue);
    expect(h.controller.isInvalidGroup, isFalse);
    expect(h.controller.groupMembersInfo?.userID, 'me');
    h.controller.close();
  });

  testWidgets('self join event supersedes a pending negative verification',
      (tester) async {
    final old = Completer<bool>();
    var joined = false;
    final h = ChatGroupHarness(
      isJoined: (_) async => joined,
      verifyMembership: (_, __) => old.future,
    );
    h.controller.initialize();
    h.controller.recover();
    await tester.pump();
    joined = true;
    h.added.add(GroupMembersInfo(
        groupID: 'group', userID: 'me', roleLevel: GroupRoleLevel.member));
    old.complete(false);
    await tester.pump();
    expect(h.controller.isInGroup.value, isTrue);
    expect(h.controller.membershipPending.value, isFalse);
    expect(h.inputCleared, 0);
    h.controller.close();
  });

  for (final event in ['leave', 'remove', 'close', 'account']) {
    testWidgets('$event invalidates an older positive server response',
        (tester) async {
      final server = Completer<bool>();
      final h = ChatGroupHarness(
        isJoined: (_) async => false,
        verifyMembership: (_, __) => server.future,
      );
      h.controller.initialize();
      h.controller.recover();
      await tester.pump();
      switch (event) {
        case 'leave':
          h.left.add(GroupInfo(groupID: 'group'));
        case 'remove':
          h.deleted.add(GroupMembersInfo(groupID: 'group', userID: 'me'));
        case 'close':
          h.controller.close();
        case 'account':
          h.userID = 'other';
      }
      server.complete(true);
      await tester.pump();
      expect(h.controller.isInGroup.value, isFalse);
      if (event == 'leave' || event == 'remove') {
        expect(h.controller.isInvalidGroup, isTrue);
      }
      expect(h.profileReads, 0);
      h.controller.close();
    });
  }

  testWidgets('sync during negative entry read starts a fresh verification',
      (tester) async {
    final old = Completer<bool>();
    var reads = 0;
    final h = ChatGroupHarness(
      isJoined: (_) async => false,
      verifyMembership: (_, __) =>
          ++reads == 1 ? old.future : Future.value(true),
    );
    h.controller.initialize();
    h.controller.recover();
    await tester.pump();
    unawaited(h.controller.refreshProfileAfterSync());
    old.complete(false);
    await tester.pump();
    expect(reads, 2);
    expect(h.controller.isInGroup.value, isTrue);
    expect(h.inputCleared, 0);
    h.controller.close();
  });

  testWidgets('member changes and other users joining cannot undo departure',
      (tester) async {
    final h = ChatGroupHarness(
      verifyMembership: (_, __) async => throw StateError('offline'),
    );
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    h.left.add(GroupInfo(groupID: 'group'));
    h.changed.add(GroupMembersInfo(groupID: 'group', userID: 'me'));
    h.added.add(GroupMembersInfo(groupID: 'group', userID: 'other'));
    h.added.add(GroupMembersInfo(groupID: 'other', userID: 'me'));
    unawaited(h.controller.refreshProfileAfterSync());
    await tester.pump();
    expect(h.controller.isInvalidGroup, isTrue);
    expect(h.controller.isInGroup.value, isFalse);
    h.controller.close();
  });
}
