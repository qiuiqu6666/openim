import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/chat/group/identity/group_sender_avatars.dart';

void main() {
  Message message(String face, int time, {String sender = 'peer'}) => Message()
    ..sendID = sender
    ..senderFaceUrl = face
    ..sendTime = time;
  test('new messages unify old rows and older pages cannot roll avatars back',
      () {
    final avatars = GroupSenderAvatars(isCurrent: () => true, lookup: null);
    final old = message('old', 10), fresh = message('new', 20);
    avatars.sync([old, fresh]);
    expect(avatars.faceFor(old), 'new');
    avatars.sync([message('ancient', 1), old]);
    expect(avatars.faceFor(old), 'new');
    avatars.update('peer', 'profile');
    avatars.sync([old]);
    expect(avatars.faceFor(old), 'profile');
    avatars.close();
  });
  test('entry reads current member avatar once per sender, not per message',
      () async {
    var reads = 0;
    final avatars = GroupSenderAvatars(
        isCurrent: () => true,
        lookup: (ids) async {
          reads++;
          expect(ids, ['peer']);
          return [GroupMembersInfo(userID: 'peer', faceURL: 'current')];
        });
    final old = message('old', 10);
    avatars.sync([old, old]);
    await Future<void>.delayed(Duration.zero);
    expect(avatars.faceFor(old), 'current');
    avatars.sync([old]);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    avatars.close();
  });
  test('member event wins over an older in-flight lookup', () async {
    final pending = Completer<List<GroupMembersInfo>>();
    final avatars = GroupSenderAvatars(
        isCurrent: () => true, lookup: (_) => pending.future);
    final old = message('old', 10);
    avatars.sync([old]);
    await Future<void>.delayed(Duration.zero);
    avatars.update('peer', 'event');
    pending.complete([GroupMembersInfo(userID: 'peer', faceURL: 'stale')]);
    await Future<void>.delayed(Duration.zero);
    expect(avatars.faceFor(old), 'event');
    avatars.update('peer', '');
    expect(avatars.faceFor(old), '');
    avatars.close();
  });
  test('account switch discards late avatar lookup', () async {
    var current = true;
    final pending = Completer<List<GroupMembersInfo>>();
    final avatars = GroupSenderAvatars(
        isCurrent: () => current, lookup: (_) => pending.future);
    final old = message('old', 10);
    avatars.sync([old]);
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete([GroupMembersInfo(userID: 'peer', faceURL: 'late')]);
    await Future<void>.delayed(Duration.zero);
    expect(avatars.faceFor(old), 'old');
    avatars.close();
  });
}
