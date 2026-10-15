import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/chat_group_sources.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_source.dart';
import 'package:openim/pages/chat/group/identity/group_sender_avatars.dart';

void main() {
  test(
      'production member query refreshes names despite stale message snapshots',
      () async {
    var name = 'Original group name';
    var reads = 0;
    final queries = ChatGroupQueries.sdk(
      identitySource: GroupMemberIdentitySource(
        currentUserID: () => 'me',
        sdkUserID: () => 'me',
        currentToken: () => 'test-token',
        baseURL: () => 'https://im.example',
        poster: (url, data, options) async {
          reads++;
          expect(url, 'https://im.example/group/get_group_members_info');
          expect(data, {
            'groupID': 'group',
            'userIDs': ['peer']
          });
          return {
            'members': [
              {'groupID': 'group', 'userID': 'peer', 'nickname': name},
              {'groupID': 'other', 'userID': 'peer', 'nickname': 'Wrong group'},
            ],
          };
        },
      ),
    );
    final identities = GroupSenderAvatars(
      isCurrent: () => true,
      lookup: (ids) => queries.members!('group', ids),
    );
    addTearDown(identities.close);
    final old = Message()
      ..sendID = 'peer'
      ..senderNickname = 'Old snapshot'
      ..sendTime = 1;
    identities.sync([old, old]);
    await Future<void>.delayed(Duration.zero);
    expect(identities.nicknameFor(old), name);
    expect(reads, 1);

    name = 'Renamed group member';
    identities.refreshMember('peer');
    await Future<void>.delayed(Duration.zero);
    expect(identities.nicknameFor(old), name);
    expect(reads, 2);

    final incoming = Message()
      ..sendID = 'peer'
      ..senderNickname = 'Old snapshot'
      ..sendTime = 2;
    identities.sync([old, incoming]);
    await Future<void>.delayed(Duration.zero);
    expect(identities.nicknameFor(incoming), name);
    expect(reads, 2);

    name = 'Latest group name';
    incoming.senderNickname = name;
    incoming.sendTime = 3;
    identities.sync([old, incoming]);
    await Future<void>.delayed(Duration.zero);
    expect(identities.nicknameFor(old), name);
    expect(reads, 3);
  });
}
