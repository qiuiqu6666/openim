import 'dart:async';
import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_sender_avatars.dart';

Message notice(String name, int time) => Message.fromJson({
      'groupID': 'group',
      'sendTime': time,
      'contentType': MessageType.memberQuitNotification,
      'notificationElem': {
        'detail': jsonEncode({
          'quitUser': {'userID': 'peer', 'nickname': name}
        })
      }
    });
String nameFor(GroupSenderAvatars cache, Message message) =>
    jsonDecode(cache.noticeFor(message).notificationElem!.detail!)['quitUser']
        ['nickname'];

void main() {
  test('newer notice beats old chat nickname even when member has left',
      () async {
    final cache =
        GroupSenderAvatars(isCurrent: () => true, lookup: (_) async => []);
    addTearDown(cache.close);
    final old = Message()
      ..sendID = 'peer'
      ..senderNickname = 'old owner'
      ..sendTime = 10;
    final current = notice('latest nickname', 20);
    final original = current.notificationElem!.detail;
    cache.sync([old, current]);
    await Future<void>.delayed(Duration.zero);
    expect(nameFor(cache, current), 'latest nickname');
    cache.sync([notice('ancient', 1), old]);
    expect(nameFor(cache, current), 'latest nickname');
    cache.updateNickname('peer', 'renamed again');
    expect(nameFor(cache, current), 'renamed again');
    expect(current.notificationElem!.detail, original);
  });

  test('departed user profile supplies newest name and ignores unrelated IDs',
      () async {
    final cache = GroupSenderAvatars(
        isCurrent: () => true,
        lookup: (_) async => [],
        lookupProfiles: (ids) async {
          expect(ids, ['peer']);
          return [
            GroupMembersInfo(userID: 'peer', nickname: 'current profile'),
            GroupMembersInfo(userID: 'other', nickname: 'unrelated')
          ];
        });
    addTearDown(cache.close);
    final message = notice('event name', 20);
    cache.sync([message]);
    await Future<void>.delayed(Duration.zero);
    expect(nameFor(cache, message), 'current profile');
    cache.sync([notice('stale event', 30)]);
    expect(nameFor(cache, message), 'current profile');
  });

  test('profile result cannot overwrite rename event or closed session',
      () async {
    var active = true;
    final pending = Completer<List<GroupMembersInfo>>();
    final cache = GroupSenderAvatars(
        isCurrent: () => active,
        lookup: (_) async => [],
        lookupProfiles: (_) => pending.future);
    addTearDown(cache.close);
    final message = notice('event name', 20);
    cache.sync([message]);
    await Future<void>.delayed(Duration.zero);
    cache.updateNickname('peer', 'live rename');
    pending
        .complete([GroupMembersInfo(userID: 'peer', nickname: 'stale reply')]);
    await Future<void>.delayed(Duration.zero);
    expect(nameFor(cache, message), 'live rename');
    active = false;
    cache.updateNickname('peer', 'after logout');
    expect(nameFor(cache, message), 'live rename');
  });

  test('profile failure keeps latest notification snapshot', () async {
    final cache = GroupSenderAvatars(
        isCurrent: () => true,
        lookup: (_) async => [],
        lookupProfiles: (_) async => throw StateError('offline'));
    addTearDown(cache.close);
    final message = notice('latest known', 20);
    cache.sync([message]);
    await Future<void>.delayed(Duration.zero);
    expect(nameFor(cache, message), 'latest known');
  });
}
