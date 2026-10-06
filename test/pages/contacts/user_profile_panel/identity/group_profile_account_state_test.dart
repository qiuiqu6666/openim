import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_info.dart';
import 'package:openim/pages/contacts/user_profile_panel/identity/group_profile_account_state.dart';

GroupMemberIdentityInfo _member({
  String groupID = 'group',
  String userID = 'im_target',
  String? account,
}) =>
    GroupMemberIdentityInfo.fromJson({
      'groupID': groupID,
      'userID': userID,
      'roleLevel': 20,
      if (account != null) 'account': account,
    });

class _Fixture {
  _Fixture() {
    state = GroupProfileAccountState(
      groupID: 'group',
      userID: 'im_target',
      owner: () => owner,
      sdkOwner: () => sdkOwner,
      token: () => token,
      server: () => server,
      load: (groupID, userIDs) {
        queries.add((groupID, userIDs));
        final result = Completer<List<GroupMemberIdentityInfo>>();
        replies.add(result);
        return result.future;
      },
    );
  }

  String? owner = 'im_owner';
  String? sdkOwner = 'im_owner';
  String? token = 'im_token';
  String server = 'http://im.test';
  late final GroupProfileAccountState state;
  final queries = <(String, List<String>)>[];
  final replies = <Completer<List<GroupMemberIdentityInfo>>>[];
}

void main() {
  test('only the matching group target supplies the public account', () async {
    final fixture = _Fixture();
    final request = fixture.state.refresh();
    expect(fixture.queries.single.$1, 'group');
    expect(fixture.queries.single.$2, ['im_target']);
    expect(fixture.state.value, isEmpty);
    fixture.replies.single.complete([
      _member(userID: 'im_other', account: '@wrong12345'),
      _member(groupID: 'other', account: '@wronggroup'),
      _member(account: '@0012345678'),
    ]);
    await request;
    expect(fixture.state.value, '@0012345678');
  });

  test('privacy change removes the old account before the response', () async {
    final fixture = _Fixture();
    final initial = fixture.state.refresh();
    fixture.replies[0].complete([_member(account: '@ab12cd34ef')]);
    await initial;
    expect(fixture.state.value, '@ab12cd34ef');
    final protected = fixture.state.refresh();
    expect(fixture.state.value, isEmpty);
    fixture.replies[1].complete([_member()]);
    await protected;
    expect(fixture.state.value, isEmpty);
    expect(fixture.state.account.value, isNull);
  });

  test('role downgrade rejects an earlier response with a public account',
      () async {
    final fixture = _Fixture();
    final old = fixture.state.refresh();
    final current = fixture.state.refresh();
    fixture.replies[1].complete([_member()]);
    await current;
    fixture.replies[0].complete([_member(account: '@ab12cd34ef')]);
    await old;
    expect(fixture.state.value, isEmpty);
  });

  test('a returned account is accepted without guessing the viewer role',
      () async {
    // The server also permits system administrators without a group role.
    final fixture = _Fixture();
    final request = fixture.state.refresh();
    fixture.replies.single.complete([_member(account: '@ab12cd34ef')]);
    await request;
    expect(fixture.state.value, '@ab12cd34ef');
  });

  for (final change in ['owner', 'sdkOwner', 'token', 'server']) {
    test('$change changes reject both late and already displayed accounts',
        () async {
      final fixture = _Fixture();
      final request = fixture.state.refresh();
      switch (change) {
        case 'owner':
          fixture.owner = 'im_other_owner';
        case 'sdkOwner':
          fixture.sdkOwner = 'im_other_owner';
        case 'token':
          fixture.token = 'rotated';
        case 'server':
          fixture.server = 'http://other.test';
      }
      fixture.replies.single.complete([_member(account: '@ab12cd34ef')]);
      await request;
      expect(fixture.state.value, isEmpty);
      final current = fixture.state.refresh();
      fixture.replies.last.complete([_member(account: '@ab12cd34ef')]);
      await current;
      expect(fixture.state.value, '@ab12cd34ef');
      fixture.token = 'logged-out-token';
      expect(fixture.state.value, isEmpty);
    });
  }

  test('failed refresh keeps the prior account revoked', () async {
    final fixture = _Fixture();
    final initial = fixture.state.refresh();
    fixture.replies[0].complete([_member(account: '@ab12cd34ef')]);
    await initial;
    final current = fixture.state.refresh();
    fixture.replies[1].completeError(StateError('offline'));
    await current;
    expect(fixture.state.value, isEmpty);
  });

  test('leaving the group invalidates a pending disclosure', () async {
    final fixture = _Fixture();
    final request = fixture.state.refresh();
    fixture.state.invalidate();
    fixture.replies.single.complete([_member(account: '@ab12cd34ef')]);
    await request;
    expect(fixture.state.value, isEmpty);
  });

  test('closed pages neither accept late accounts nor issue another query',
      () async {
    final fixture = _Fixture();
    final request = fixture.state.refresh();
    fixture.state.close();
    fixture.replies.single.complete([_member(account: '@ab12cd34ef')]);
    await request;
    await fixture.state.refresh();
    expect(fixture.state.value, isEmpty);
    expect(fixture.queries, hasLength(1));
  });

  test('signed-out pages cannot query account details', () async {
    final fixture = _Fixture()..owner = null;
    await fixture.state.refresh();
    expect(fixture.queries, isEmpty);
    expect(fixture.state.value, isEmpty);
  });
}
