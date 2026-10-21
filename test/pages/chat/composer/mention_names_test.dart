import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/composer/mention_names.dart';

void main() {
  test('non-friends with blank group names use public nicknames', () async {
    final members = [
      GroupMembersInfo(userID: 'stranger', nickname: ''),
      GroupMembersInfo(userID: 'blank', nickname: '  '),
      GroupMembersInfo(userID: 'known', nickname: '群昵称'),
    ];
    final names = await resolveMentionNames(members, loadUsers: (ids) async {
      expect(ids, ['stranger', 'blank']);
      return [
        PublicUserInfo(userID: 'stranger', nickname: '非好友昵称'),
        PublicUserInfo(userID: 'blank', nickname: '另一位成员'),
        PublicUserInfo(userID: 'known', nickname: '不应覆盖群昵称'),
      ];
    });
    expect(names, {
      'stranger': '非好友昵称',
      'blank': '另一位成员',
      'known': '群昵称',
    });
    expect(members.first.nickname, '');
  });

  test('valid group nickname needs no profile request', () async {
    var requested = false;
    expect(
        await resolveMentionNames([
          GroupMembersInfo(userID: 'peer', nickname: '成员昵称'),
          GroupMembersInfo(userID: '', nickname: 'invalid'),
        ], loadUsers: (_) async {
          requested = true;
          return [];
        }),
        {'peer': '成员昵称'});
    expect(requested, isFalse);
  });

  for (final fail in [false, true]) {
    test('unavailable nickname keeps identity (request failure=$fail)',
        () async {
      final names = await resolveMentionNames([
        GroupMembersInfo(userID: 'peer', nickname: ''),
      ], loadUsers: (_) async {
        if (fail) throw StateError('offline');
        return [PublicUserInfo(userID: 'peer', nickname: ' ')];
      });
      expect(names, {'peer': 'peer'});
    });
  }
}
