import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/group_features/sangong/services/account_identity/sangong_team_user_search.dart';

void main() {
  test('OpenIM nickname and ID search includes nonfriends, in batches of 50',
      () async {
    final batches = <int>[];
    final search = SangongTeamUserSearch(profiles: (ids) async {
      batches.add(ids.length);
      return [
        for (final id in ids)
          PublicUserInfo(userID: id, nickname: 'OpenIM昵称$id')
      ];
    });
    await search.load({for (var i = 0; i < 121; i++) 'user$i'}, () => true);
    expect(batches, [50, 50, 21]);
    expect(search.matches('user120', 'openim昵称user120'), isTrue);
    expect(search.matches('user120', 'USER120'), isTrue);
    expect(search.matches('user120', '不匹配'), isFalse);
    search.close();
  });
  test(
      'friend remark matches cannot expose someone outside the authorized team',
      () async {
    String? keyword;
    final search = SangongTeamUserSearch(friends: (query) async {
      keyword = query;
      return [
        FriendInfo(userID: 'child', remark: '客户甲'),
        FriendInfo(userID: 'outsider', remark: '客户甲')
      ];
    });
    expect(await search.searchFriends(' 客户甲 ', {'child'}), {'child'});
    expect(keyword, '客户甲');
    expect(await search.searchFriends('客户甲', {}), isEmpty);
    search.close();
  });
  test('late old-scope names cannot overwrite the new team', () async {
    final old = Completer<List<PublicUserInfo>>();
    final search = SangongTeamUserSearch(
        profiles: (ids) => ids.contains('old')
            ? old.future
            : Future.value([PublicUserInfo(userID: 'new', nickname: '新昵称')]));
    final first = search.load({'old'}, () => true);
    await search.load({'new'}, () => true);
    old.complete([PublicUserInfo(userID: 'old', nickname: '旧昵称')]);
    await first;
    expect(search.matches('old', '旧昵称'), isFalse);
    expect(search.matches('new', '新昵称'), isTrue);
    search.close();
  });
  test('closing or account invalidation rejects late profiles', () async {
    final pending = Completer<List<PublicUserInfo>>();
    var current = true;
    final search = SangongTeamUserSearch(profiles: (_) => pending.future);
    final work = search.load({'child'}, () => current);
    current = false;
    pending.complete([PublicUserInfo(userID: 'child', nickname: '禁止写入')]);
    await work;
    expect(search.matches('child', '禁止写入'), isFalse);
    search.close();
  });
}
