import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_sender_avatars.dart';
import '../support/chat_group_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recovery batches loaded senders and preserves a newer member event',
      () async {
    final calls = <List<String>>[];
    final pending = Completer<List<GroupMembersInfo>>();
    final identities = GroupSenderAvatars(
      isCurrent: () => true,
      lookup: (ids) async {
        calls.add(List.of(ids));
        if (calls.length == 1) return pending.future;
        return [
          for (final id in ids)
            GroupMembersInfo(userID: id, nickname: 'Loaded', faceURL: 'loaded')
        ];
      },
    );
    addTearDown(identities.close);
    final messages = [for (var i = 0; i < 121; i++) Message(sendID: 'user-$i')];
    identities.refreshMessages([...messages, ...messages]);
    await Future<void>.delayed(Duration.zero);
    identities.updateNickname('user-0', 'Live name');
    identities.update('user-0', 'live-avatar');
    pending.complete([
      for (final id in calls.first)
        GroupMembersInfo(
            userID: id, nickname: 'Old name', faceURL: 'old-avatar')
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((ids) => ids.length), [50, 50, 21]);
    expect(calls.expand((ids) => ids).toSet(), hasLength(121));
    expect(identities.nicknameFor(messages.first), 'Live name');
    expect(identities.faceFor(messages.first), 'live-avatar');
    identities.refreshMessages([messages.last]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last, ['user-120']);
    identities.close();
    identities.refreshMessages(messages);
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(4));
  });

  testWidgets('reconnect refreshes loaded senders without a member event',
      (tester) async {
    var name = 'Old name';
    var face = 'old-avatar';
    final requests = <List<String>>[];
    final h = ChatGroupHarness(members: (group, ids) async {
      requests.add(List.of(ids));
      return [
        for (final id in ids)
          GroupMembersInfo(
              groupID: group, userID: id, nickname: name, faceURL: face)
      ];
    });
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    final message = Message(
        sendID: 'peer',
        senderNickname: 'Snapshot',
        senderFaceUrl: 'snapshot',
        sendTime: 1);
    h.messages.addAll([message, message]);
    await tester.pump();
    expect(h.controller.nicknameFor(message), 'Old name');
    final before = requests.length;
    name = 'Changed while offline';
    face = '';
    final first = h.controller.refreshProfileAfterSync();
    final duplicate = h.controller.refreshProfileAfterSync();
    await Future.wait([first, duplicate]);
    await tester.pump();
    expect(h.controller.nicknameFor(message), name);
    expect(h.controller.avatarFor(message), '');
    expect(requests.length, before + 1);
    expect(requests.last, ['peer']);
  });
}
