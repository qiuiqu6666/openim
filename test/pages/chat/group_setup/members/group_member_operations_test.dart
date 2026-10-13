import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group_setup/members/group_member_operations.dart';
import 'package:openim/pages/chat/group_setup/members/group_member_batch_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('partial SDK results and missing receipts retain only unconfirmed IDs',
      () {
    final result = GroupMemberBatchResult.parse([
      {'userID': 'accepted', 'result': 0},
      {'userID': 'denied', 'result': 1002},
    ], [
      'accepted',
      'denied',
      'missing'
    ]);
    expect(result.succeeded, {'accepted'});
    expect(result.failed, {'denied', 'missing'});
    expect(GroupMemberBatchResult.parse('""', ['accepted']).failed, isEmpty);
    expect(GroupMemberBatchResult.parse('malformed', ['accepted']).failed,
        {'accepted'});
  });

  test(
      'failed invitation shows feedback and next picker preselects failed users only',
      () async {
    final selections = <List<String?>>[];
    final writes = <List<String>>[];
    final feedback = <String>[];
    var refreshes = 0;
    final operations = GroupMemberOperations(
      captureCurrent: () => () => true,
      groupInfo: () => GroupInfo(groupID: 'g'),
      canRemove: () => true,
      refreshMembers: () async {
        refreshes++;
      },
      pickInvites: (_, retry) async {
        selections.add(retry.map((user) => user.userID).toList());
        return retry.isEmpty
            ? [UserInfo(userID: 'accepted'), UserInfo(userID: 'denied')]
            : retry;
      },
      invite: (_, ids) async {
        writes.add(List.of(ids));
        return writes.length == 1
            ? [
                {'userID': 'accepted', 'result': 0},
                {'userID': 'denied', 'result': 1002}
              ]
            : '""';
      },
      showFeedback: feedback.add,
    );
    addTearDown(operations.close);
    await operations.inviteMembers();
    await operations.inviteMembers();
    expect(selections, [
      [],
      ['denied']
    ]);
    expect(writes, [
      ['accepted', 'denied'],
      ['denied']
    ]);
    expect(feedback, hasLength(2));
    expect(feedback.first, contains('1'));
    expect(refreshes, 2);
  });

  test(
      'failed removal is explicitly retried without resending accepted members',
      () async {
    final writes = <List<String>>[];
    final retryCounts = <int>[];
    var selections = 0;
    final operations = GroupMemberOperations(
      captureCurrent: () => () => true,
      groupInfo: () => GroupInfo(groupID: 'g'),
      canRemove: () => true,
      refreshMembers: () async {},
      pickRemovals: (_) async {
        selections++;
        return [
          GroupMembersInfo(userID: 'accepted'),
          GroupMembersInfo(userID: 'denied')
        ];
      },
      chooseRetry: (count) async {
        retryCounts.add(count);
        return true;
      },
      remove: (_, ids) async {
        writes.add(List.of(ids));
        return writes.length == 1
            ? [
                {'userID': 'accepted', 'result': 0},
                {'userID': 'denied', 'result': 1002}
              ]
            : '""';
      },
      showFeedback: (_) {},
    );
    addTearDown(operations.close);
    await operations.removeMembers();
    await operations.removeMembers();
    expect(selections, 1);
    expect(retryCounts, [1]);
    expect(writes, [
      ['accepted', 'denied'],
      ['denied']
    ]);
  });

  test(
      'permission change during picking stops dispatch and releases the action',
      () async {
    var permitted = true, calls = 0;
    final picker = Completer<List<GroupMembersInfo>?>();
    final operations = GroupMemberOperations(
      captureCurrent: () => () => permitted,
      groupInfo: () => GroupInfo(groupID: 'g'),
      canRemove: () => permitted,
      refreshMembers: () async {},
      pickRemovals: (_) => picker.future,
      remove: (_, __) async {
        calls++;
        return '';
      },
      showFeedback: (_) {},
    );
    addTearDown(operations.close);
    final pending = operations.removeMembers();
    permitted = false;
    picker.complete([GroupMembersInfo(userID: 'peer')]);
    await pending;
    expect(calls, 0);
  });

  test(
      'transport failure retains IDs and reports failure without an uncaught error',
      () async {
    final selections = <List<String?>>[];
    final feedback = <String>[];
    final operations = GroupMemberOperations(
      captureCurrent: () => () => true,
      groupInfo: () => GroupInfo(groupID: 'g'),
      canRemove: () => true,
      refreshMembers: () async {},
      pickInvites: (_, retry) async {
        selections.add(retry.map((user) => user.userID).toList());
        return [UserInfo(userID: 'peer')];
      },
      invite: (_, __) async => throw StateError('offline'),
      showFeedback: feedback.add,
    );
    addTearDown(operations.close);
    await operations.inviteMembers();
    await operations.inviteMembers();
    expect(selections, [
      [],
      ['peer']
    ]);
    expect(feedback, hasLength(2));
  });
}
