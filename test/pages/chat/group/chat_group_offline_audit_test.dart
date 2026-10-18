import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_group_harness.dart';

// Offline recovery ordering and bounded retries.
void main() {
  testWidgets('late group callback repairs name and count after an old read',
      (tester) async {
    final h = ChatGroupHarness();
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    await h.controller.refreshProfileAfterSync();
    expect(h.controller.memberCount.value, 5);
    h.groupChanged.add(GroupInfo(
        groupID: 'group', groupName: 'Renamed offline', memberCount: 8));
    await tester.pump();
    expect(h.profiles.last.$1, 'Renamed offline');
    expect(h.controller.memberCount.value, 8);
  });

  testWidgets('a subsequent profile refresh reads updated local metadata',
      (tester) async {
    var name = 'Old';
    var count = 5;
    final h = ChatGroupHarness(
        groupInfo: (id) async => [
              GroupInfo(groupID: id, groupName: name, memberCount: count),
            ]);
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    await h.controller.refreshProfileAfterSync();
    name = 'New';
    count = 8;
    h.controller.recover(resetAttempts: true);
    await tester.pump(const Duration(seconds: 30));
    expect(h.profileReads, 2);
    expect(h.profiles.last.$1, 'Old');
    expect(h.controller.memberCount.value, 5);
    await h.controller.refreshProfileAfterSync();
    expect(h.profiles.last.$1, 'New');
    expect(h.controller.memberCount.value, 8);
  });

  testWidgets('post-sync profile failure retries automatically',
      (tester) async {
    var fail = false;
    final h = ChatGroupHarness(groupInfo: (id) async {
      if (fail) throw StateError('temporary network failure');
      return [GroupInfo(groupID: id, groupName: 'Group', memberCount: 5)];
    });
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    fail = true;
    await h.controller.refreshProfileAfterSync();
    fail = false;
    await tester.pump(const Duration(seconds: 30));
    expect(h.errors, hasLength(1));
    expect(h.profileReads, 3);
  });

  testWidgets('member events require a group profile callback to update count',
      (tester) async {
    final h = ChatGroupHarness();
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    h.added.add(GroupMembersInfo(groupID: 'group', userID: 'new-member'));
    await tester.pump();
    expect(h.controller.memberCount.value, 5);
    h.groupChanged.add(GroupInfo(groupID: 'group', memberCount: 6));
    expect(h.controller.memberCount.value, 6);
    h.deleted.add(GroupMembersInfo(groupID: 'group', userID: 'new-member'));
    await tester.pump();
    expect(h.controller.memberCount.value, 6);
    h.groupChanged.add(GroupInfo(groupID: 'group', memberCount: 5));
    expect(h.controller.memberCount.value, 5);
  });

  for (final stop in ['exhausted', 'event', 'leave', 'close', 'account']) {
    testWidgets('profile retry is bounded and respects $stop', (tester) async {
      var fail = false;
      final h = ChatGroupHarness(groupInfo: (id) async {
        if (fail) throw StateError('offline');
        return [GroupInfo(groupID: id, groupName: 'Old', memberCount: 5)];
      });
      h.controller.initialize();
      await h.controller.loadAfterHistory();
      fail = true;
      await h.controller.refreshProfileAfterSync();
      switch (stop) {
        case 'event':
          h.groupChanged.add(
              GroupInfo(groupID: 'group', groupName: 'Fresh', memberCount: 7));
        case 'leave':
          h.left.add(GroupInfo(groupID: 'group'));
        case 'close':
          h.controller.close();
        case 'account':
          h.userID = 'another-account';
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(minutes: 1));
      expect(h.profileReads, stop == 'exhausted' ? 4 : 2);
      if (stop == 'event') {
        expect(h.profiles.last.$1, 'Fresh');
        expect(h.controller.memberCount.value, 7);
      }
    });
  }
}
