import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_identity_state.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

GroupMemberIdentitySource sourceWith(GroupMemberIdentityPoster poster) =>
    GroupMemberIdentitySource(
      poster: poster,
      currentUserID: () => 'viewer',
      currentToken: () => 'im-token',
      baseURL: () => 'https://im.test',
    );

Map<String, dynamic> response({String? account, String id = 'im_peer'}) => {
      'members': [
        {
          'groupID': 'group',
          'userID': id,
          'nickname': 'Peer',
          'roleLevel': GroupRoleLevel.member,
          if (account != null) 'account': account,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'viewer';
  });

  test('authority pages preserve IM IDs and omit unavailable accounts',
      () async {
    final requests = <Map<String, dynamic>>[];
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) async {
        requests.add(data);
        return response(account: requests.length == 1 ? '1234567890' : null);
      }),
    );
    final first =
        await state.list(groupID: 'group', pageNumber: 1, showNumber: 100);
    final second =
        await state.list(groupID: 'group', pageNumber: 2, showNumber: 100);
    expect(first!.single.userID, 'im_peer');
    expect(GroupMemberIdentityState.accountOf(first.single), '1234567890');
    expect(second!.single.userID, 'im_peer');
    expect(GroupMemberIdentityState.accountOf(second.single), isEmpty);
    expect(requests.last['pagination'], {'pageNumber': 2, 'showNumber': 100});
  });

  test('SDK search accounts come only from matching group authority rows',
      () async {
    Map<String, dynamic>? request;
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) async {
        request = data;
        return {
          'members': [
            {'groupID': 'group', 'userID': 'im_peer', 'account': '@abcdefgh12'},
            {
              'groupID': 'other',
              'userID': 'im_hidden',
              'account': '9999999999'
            },
          ],
        };
      }),
    );
    final sdkRows = [
      GroupMembersInfo(
          groupID: 'group', userID: 'im_peer', nickname: 'SDK name'),
      GroupMemberIdentityInfo(
          groupID: 'group', userID: 'im_hidden', account: 'old'),
    ];
    final result = await state.searchIdentities('group', sdkRows);
    expect(request!['userIDs'], ['im_peer', 'im_hidden']);
    expect(result!.first.userID, 'im_peer');
    expect(result.first.nickname, 'SDK name');
    expect(result.first.account, '@abcdefgh12');
    expect(result.last.userID, 'im_hidden');
    expect(result.last.account, isNull);
    expect(GroupMemberIdentityState.accountOf(sdkRows.first), isEmpty);
  });

  for (final invalidation in ['permissions', 'session', 'close']) {
    test('late $invalidation page cannot restore an old account', () async {
      final pending = Completer<dynamic>();
      var session = 'first';
      final state = GroupMemberIdentityState(
        session: () => session,
        source: sourceWith((url, data, options) => pending.future),
      );
      final result =
          state.list(groupID: 'group', pageNumber: 1, showNumber: 100);
      switch (invalidation) {
        case 'permissions':
          state.invalidate();
        case 'session':
          session = 'second';
        case 'close':
          state.close();
      }
      pending.complete(response(account: '1234567890'));
      expect(await result, isNull);
    });
  }

  test(
      'late search enrichment and rule refresh cannot cross permission generations',
      () async {
    final pendingMembers = Completer<dynamic>();
    final pendingRules = Completer<GroupMemberIdentityRules>();
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) => pendingMembers.future),
      rulesLoader: (_) => pendingRules.future,
    );
    final search = state.searchIdentities('group', [
      GroupMembersInfo(groupID: 'group', userID: 'im_peer'),
    ]);
    final rules = state.rules('group');
    state.invalidate();
    pendingMembers.complete(response(account: '1234567890'));
    pendingRules.complete((group: GroupInfo(groupID: 'group'), self: null));
    expect(await search, isNull);
    expect(await rules, isNull);
  });
}
