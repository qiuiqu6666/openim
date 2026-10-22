import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_source.dart';

void main() {
  for (final joined in [true, false]) {
    test('permission denial requires directory confirmation: joined=$joined',
        () async {
      final calls = <String>[];
      final source = GroupMemberIdentitySource(
        currentUserID: () => 'me',
        sdkUserID: () => 'me',
        currentToken: () => 'token',
        baseURL: () => 'https://im.test',
        poster: (url, body, options) async {
          calls.add(url);
          if (url.endsWith('get_group_members_info')) {
            return {'errCode': 1002, 'errMsg': 'permission denied'};
          }
          return {
            'groupIDs': [if (joined) 'group']
          };
        },
      );
      expect(
          await source.containsMember(groupID: 'group', userID: 'me'), joined);
      expect(calls, hasLength(2));
      expect(calls.last, endsWith('/group/get_full_join_group_ids'));
    });
  }
  test('malformed authority is not proof of departure', () async {
    final source = GroupMemberIdentitySource(
      currentUserID: () => 'me',
      sdkUserID: () => 'me',
      currentToken: () => 'token',
      baseURL: () => 'https://im.test',
      poster: (url, body, options) async =>
          url.endsWith('get_group_members_info')
              ? {'errCode': 1002, 'errMsg': 'denied'}
              : <String, dynamic>{},
    );
    await expectLater(source.containsMember(groupID: 'group', userID: 'me'),
        throwsFormatException);
  });
  test('network error does not revoke membership or trigger a directory read',
      () async {
    var calls = 0;
    final source = GroupMemberIdentitySource(
      currentUserID: () => 'me',
      sdkUserID: () => 'me',
      currentToken: () => 'token',
      baseURL: () => 'https://im.test',
      poster: (url, body, options) async {
        calls++;
        throw StateError('offline');
      },
    );
    await expectLater(source.containsMember(groupID: 'group', userID: 'me'),
        throwsStateError);
    expect(calls, 1);
  });
}
